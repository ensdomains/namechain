import { shouldSupportInterfaces } from "@ensdomains/hardhat-chai-matchers-viem/behaviour";
import { serve } from "@namestone/ezccip/serve";
import { BrowserProvider } from "ethers/providers";
import hre from "hardhat";
import { readFileSync } from "node:fs";
import {
  bytesToHex,
  concat,
  encodeErrorResult,
  encodeFunctionData,
  keccak256,
  labelhash,
  namehash,
  parseAbi,
  toHex,
} from "viem";
import { afterAll, afterEach, describe, expect, it } from "vitest";

import { Gateway } from "../../../lib/unruggable-gateways/src/gateway.js";
import { UncheckedRollup } from "../../../lib/unruggable-gateways/src/UncheckedRollup.js";
import { expectVar } from "../../utils/expectVar.js";
import { injectRPCCounter } from "../../utils/hardhat-counter.js";
import {
  COIN_TYPE_DEFAULT,
  COIN_TYPE_ETH,
  type KnownProfile,
  PROFILE_ABI,
  bundleCalls,
  makeResolutions,
} from "../../utils/resolutions.js";
import { shouldSupportFeatures } from "../../utils/supportsFeatures.js";
import { dnsEncodeName, getLabelAt, splitName } from "../../utils/utils.js";
import { deployArtifact } from "../fixtures/deployArtifact.js";
import { deployV1Fixture } from "../fixtures/deployV1Fixture.js";
import { deployV2Fixture } from "../fixtures/deployV2Fixture.js";
import { urgArtifact } from "../fixtures/externalArtifacts.js";

let urgCount = 0;
const chain1 = injectRPCCounter(await hre.network.connect());
const chain2 = injectRPCCounter(await hre.network.connect());
const chains = [chain1, chain2];

async function sync() {
  const blocks = await Promise.all(
    chains.map(async (c) => {
      const counts = { ...c.counts }; // save counts
      const client = await c.viem.getPublicClient();
      const { timestamp: t } = await client.getBlock();
      return { t, counts };
    }),
  );
  const tMax = blocks.reduce((a, x) => (x.t > a ? x.t : a), 0n) + 1n;
  await Promise.all(
    chains.map(async (c, i) => {
      await c.networkHelpers.time.setNextBlockTimestamp(tMax);
      await c.networkHelpers.mine(1);
      c.counts = blocks[i].counts; // restore counts
    }),
  );
}

function namechainFixture() {
  return deployV2Fixture(chain2);
}

async function fixture() {
  const mainnetV1 = await deployV1Fixture(chain1, true); // CCIP on UR
  const mainnetV2 = await deployV2Fixture(chain1, true); // CCIP on UR
  const namechain = await chain2.networkHelpers.loadFixture(namechainFixture);
  const gateway = new Gateway(
    new UncheckedRollup(new BrowserProvider(chain2.provider)),
  );
  gateway.disableCache();
  const ccip = await serve(gateway, {
    protocol: "raw",
    log() {
      urgCount++;
    },
  });
  afterAll(ccip.shutdown);
  const GatewayVM = await deployArtifact(mainnetV2.walletClient, {
    file: urgArtifact("GatewayVM"),
  });
  const hooksAddress = await deployArtifact(mainnetV2.walletClient, {
    file: urgArtifact("UncheckedVerifierHooks"),
  });
  const verifierAddress = await deployArtifact(mainnetV2.walletClient, {
    file: urgArtifact("UncheckedVerifier"),
    args: [[ccip.endpoint], 0, hooksAddress],
    libs: { GatewayVM },
  });
  const ethResolver = await mainnetV2.deployDedicatedResolver();
  const mockBridgeController = await chain1.viem.deployContract(
    "MockBridgeController",
  );
  const ethTLDResolver = await chain1.viem.deployContract(
    "ETHTLDResolver",
    [
      mainnetV1.nameWrapper.address,
      mainnetV1.batchGatewayProvider.address,
      mockBridgeController.address,
      ethResolver.address,
      verifierAddress,
      namechain.datastore.address,
      namechain.ethRegistry.address,
    ],
    { client: { public: mainnetV2.publicClient } }, // CCIP on EFR
  );
  await mainnetV2.rootRegistry.write.setResolver([
    BigInt(labelhash("eth")),
    ethTLDResolver.address,
  ]);
  return {
    ethTLDResolver,
    ethResolver,
    mainnetV1,
    mockBridgeController,
    mainnetV2,
    namechain,
    gateway,
    verifierAddress,
  } as const;
}

const loadFixture = async () => {
  await chain2.networkHelpers.loadFixture(namechainFixture);
  return chain1.networkHelpers.loadFixture(fixture);
};

const dummySelector = "0x12345678";
const testAddress = "0x8000000000000000000000000000000000000001";
const testNames = ["test.eth", "a.b.c.test.eth"];

describe("ETHTLDResolver", () => {
  const rpcs: Record<string, any> = {};
  afterEach(({ expect: { getState } }) => {
    rpcs[getState().currentTestName!.split(" > ").slice(1).join("/")] = {
      L1: chain1.counts.eth_call || 0,
      L2: chain2.counts.eth_call || 0,
      Urg: urgCount,
      Slots: chain2.counts.eth_getStorageAt || 0,
    };
    chain1.counts = {};
    chain2.counts = {};
    urgCount = 0;
  });
  afterAll(() => console.table(rpcs));

  shouldSupportInterfaces({
    contract: () => loadFixture().then((F) => F.ethTLDResolver),
    interfaces: ["IERC165", "IERC7996", "IExtendedResolver"],
  });

  shouldSupportFeatures({
    contract: () => loadFixture().then((F) => F.ethTLDResolver),
    features: {
      RESOLVER: ["RESOLVE_MULTICALL"],
    },
  });

  describe("storage layout", () => {
    describe("DedicatedResolver", () => {
      const code = readFileSync(
        new URL(
          "../../../src/common/resolver/libraries/DedicatedResolverLayoutLib.sol",
          import.meta.url,
        ),
        "utf8",
      );
      for (const [_, name, slot] of code.matchAll(
        /constant (SLOT_\S+) = (\S+);/g,
      )) {
        it(`${name} = ${slot}`, async () => {
          const storageLayout =
            await hre.artifacts.getStorageLayout("DedicatedResolver");
          const label = name.slice(4).toLowerCase(); // "SLOT_ABC" => "_abc"
          const ref = storageLayout.storage.find((x) =>
            x.label.startsWith(label),
          );
          expect(ref?.slot).toEqual(slot);
        });
      }
    });
    describe("RegistryDatastore", () => {
      it("SLOT_RD_ENTRIES = 0", async () => {
        const {
          storage: [{ slot, label }],
        } = await hre.artifacts.getStorageLayout("RegistryDatastore");
        expectVar({ slot }).toStrictEqual("0");
        expectVar({ label }).toStrictEqual("_entries");
      });
    });
  });

  describe("urg", () => {
    it("namechainVerifier", async () => {
      const F = await loadFixture();
      const address = await F.ethTLDResolver.read.namechainVerifier();
      expectVar({ address }).toEqualAddress(F.verifierAddress);
    });
    it("setNamechainVerifier", async () => {
      const F = await loadFixture();
      await F.ethTLDResolver.write.setNamechainVerifier([testAddress]);
      const address = await F.ethTLDResolver.read.namechainVerifier();
      expectVar({ address }).toEqualAddress(testAddress);
    });
  });

  describe("eth", () => {
    it("ethResolver", async () => {
      const F = await loadFixture();
      const address = await F.ethTLDResolver.read.ethResolver();
      expectVar({ address }).toEqualAddress(F.ethResolver.address);
    });
    it("setETHResolver", async () => {
      const F = await loadFixture();
      const resolver = await F.mainnetV2.deployDedicatedResolver();
      await F.ethTLDResolver.write.setETHResolver([resolver.address]);
      const address = await F.ethTLDResolver.read.ethResolver();
      expectVar({ address }).toEqualAddress(resolver.address);
    });
    it("resolve", async () => {
      const F = await loadFixture();
      const kp: KnownProfile = {
        name: "eth",
        addresses: [{ coinType: COIN_TYPE_ETH, value: testAddress }],
      };
      const [res] = makeResolutions(kp);
      await F.ethResolver.write.multicall([[res.writeDedicated]]);
      await sync();
      const [answer, resolver] =
        await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(kp.name),
          res.call,
        ]);
      expectVar({ resolver }).toEqualAddress(F.ethTLDResolver.address);
      res.expect(answer);
    });
  });

  describe("unregistered", () => {
    for (const name of testNames) {
      it(name, async () => {
        const F = await loadFixture();
        const [res] = makeResolutions({
          name,
          addresses: [{ coinType: COIN_TYPE_ETH, value: testAddress }],
        });
        await sync();
        await expect(
          F.mainnetV1.universalResolver.read.resolve([
            dnsEncodeName(name),
            res.call,
          ]),
        ).toBeRevertedWithCustomError("ResolverNotFound");
        // the errors are different because:
        // V1: requireResolver() fails
        // V2: gateway to namechain, no resolver found
        await expect(
          F.mainnetV2.universalResolver.read.resolve([
            dnsEncodeName(name),
            res.call,
          ]),
        )
          .toBeRevertedWithCustomError("ResolverError")
          .withArgs([
            encodeErrorResult({
              abi: F.ethTLDResolver.abi,
              errorName: "UnreachableName",
              args: [dnsEncodeName(name)],
            }),
          ]);
      });
    }
  });

  describe("still registered on V1", () => {
    for (const name of testNames) {
      it(name, async () => {
        const F = await loadFixture();
        const kp: KnownProfile = {
          name,
          addresses: [{ coinType: COIN_TYPE_ETH, value: testAddress }],
        };
        const [res] = makeResolutions(kp);
        await F.mainnetV1.setupName(kp);
        await F.mainnetV1.publicResolver.write.multicall([[res.write]]);
        await sync();
        const [answer, resolver] =
          await F.mainnetV2.universalResolver.read.resolve([
            dnsEncodeName(kp.name),
            res.call,
          ]);
        expectVar({ resolver }).toEqualAddress(F.ethTLDResolver.address);
        res.expect(answer);
      });
    }
  });

  describe("migrated from V1", () => {
    for (const name of testNames) {
      it(name, async () => {
        const F = await loadFixture();
        const kp: KnownProfile = {
          name,
          addresses: [{ coinType: COIN_TYPE_ETH, value: testAddress }],
        };
        const [res] = makeResolutions(kp);
        await F.mainnetV1.setupName(kp);
        const tokenId = BigInt(labelhash(getLabelAt(kp.name, -2)));
        await F.mainnetV1.ethRegistrar.write.safeTransferFrom([
          F.mainnetV1.walletClient.account.address,
          F.mockBridgeController.address,
          tokenId,
        ]);
        const available = await F.mainnetV1.ethRegistrar.read.available([
          tokenId,
        ]);
        expectVar({ available }).toStrictEqual(false);
        const { dedicatedResolver } = await F.namechain.setupName({ name });
        await dedicatedResolver.write.multicall([[res.writeDedicated]]);
        await sync();
        const [answer, resolver] =
          await F.mainnetV2.universalResolver.read.resolve([
            dnsEncodeName(kp.name),
            res.call,
          ]);
        expectVar({ resolver }).toEqualAddress(F.ethTLDResolver.address);
        res.expect(answer);
      });
    }
  });

  describe("ejected from Namechain", () => {
    for (const name of testNames) {
      it(name, async () => {
        const F = await loadFixture();
        const kp: KnownProfile = {
          name,
          addresses: [{ coinType: COIN_TYPE_ETH, value: testAddress }],
        };
        const [res] = makeResolutions(kp);
        const { dedicatedResolver } = await F.mainnetV2.setupName(kp);
        await dedicatedResolver.write.multicall([[res.writeDedicated]]);
        await sync();
        const [answer, resolver] =
          await F.mainnetV2.universalResolver.read.resolve([
            dnsEncodeName(kp.name),
            res.call,
          ]);
        expectVar({ resolver }).toEqualAddress(dedicatedResolver.address);
        res.expect(answer);
      });
    }
  });

  describe("registered on Namechain", () => {
    for (const name of testNames) {
      it(name, async () => {
        const F = await loadFixture();
        const kp: KnownProfile = {
          name,
          addresses: [{ coinType: COIN_TYPE_ETH, value: testAddress }],
        };
        const [res] = makeResolutions(kp);
        const { dedicatedResolver } = await F.namechain.setupName(kp);
        await dedicatedResolver.write.multicall([[res.writeDedicated]]);
        await sync();
        const [answer, resolver] =
          await F.mainnetV2.universalResolver.read.resolve([
            dnsEncodeName(kp.name),
            res.call,
          ]);
        expectVar({ resolver }).toEqualAddress(F.ethTLDResolver.address);
        res.expect(answer);
      });
    }
  });

  describe("expired", () => {
    for (const name of testNames) {
      it(name, async () => {
        const F = await loadFixture();
        const kp: KnownProfile = {
          name,
          addresses: [{ coinType: COIN_TYPE_ETH, value: testAddress }],
        };
        const interval = 1000n;
        await sync();
        const { timestamp } = await F.namechain.publicClient.getBlock();
        const [res] = makeResolutions(kp);
        const { dedicatedResolver } = await F.namechain.setupName({
          name: kp.name,
          expiry: timestamp + interval,
        });
        await dedicatedResolver.write.multicall([[res.writeDedicated]]);
        await sync();
        const answer = await F.ethTLDResolver.read.resolve([
          dnsEncodeName(kp.name),
          res.call,
        ]);
        res.expect(answer);
        await chain2.networkHelpers.mine(2, { interval }); // wait for the name to expire
        await sync();
        await expect(
          F.ethTLDResolver.read.resolve([dnsEncodeName(kp.name), res.call]),
        ).toBeRevertedWithCustomError("UnreachableName");
        // await expect(
        //   F.mainnetV2.universalResolver.read.resolve([
        //     dnsEncodeName(kp.name),
        //     res.call,
        //   ]),
        // )
        //   .toBeRevertedWithCustomError("ResolverError")
        //   .withArgs(
        //     encodeErrorResult({
        //       abi: F.ETHTLDResolver.abi,
        //       errorName: "UnreachableName",
        //       args: [dnsEncodeName(kp.name)],
        //     }),
        //   );
      });
    }
  });

  describe("profile support", () => {
    const kp: KnownProfile = {
      name: testNames[0],
      primary: { value: testNames[0] },
      addresses: [
        { coinType: COIN_TYPE_ETH, value: testAddress },
        { coinType: COIN_TYPE_DEFAULT, value: testAddress },
        { coinType: 0n, value: concat([keccak256("0x0"), "0x01"]) },
      ],
      texts: [{ key: "url", value: "https://ens.domains" }],
      contenthash: { value: concat([keccak256("0x1"), "0x01"]) },
      pubkey: { x: keccak256("0x2"), y: keccak256("0x3") },
      abis: [{ contentType: 8n, value: concat([keccak256("0x4"), "0x01"]) }],
      interfaces: [{ selector: dummySelector, value: testAddress }],
      errors: [
        {
          call: dummySelector,
          answer: encodeErrorResult({
            abi: parseAbi(["error UnsupportedResolverProfile(bytes4)"]),
            args: [dummySelector],
          }),
        },
      ],
    };
    it("unsupported", async () => {
      const F = await loadFixture();
      await sync();
      await expect(
        F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(kp.name),
          dummySelector,
        ]),
      )
        .toBeRevertedWithCustomError("UnsupportedResolverProfile")
        .withArgs([dummySelector]);
    });
    for (const res of makeResolutions(kp)) {
      if (res.write.length <= 2) continue;
      it(res.desc, async () => {
        const F = await loadFixture();
        const { dedicatedResolver } = await F.namechain.setupName(kp);
        await dedicatedResolver.write.multicall([[res.writeDedicated]]);
        await sync();
        const [answer, resolver] =
          await F.mainnetV2.universalResolver.read.resolve([
            dnsEncodeName(kp.name),
            res.call,
          ]);
        expectVar({ resolver }).toEqualAddress(F.ethTLDResolver.address);
        res.expect(answer);
      });
    }
    it("hasAddr()", async () => {
      const F = await loadFixture();
      const kp: KnownProfile = {
        name: testNames[0],
        hasAddresses: [
          { coinType: COIN_TYPE_ETH, exists: false },
          { coinType: COIN_TYPE_DEFAULT, exists: true },
          { coinType: COIN_TYPE_DEFAULT | 1n, exists: false },
          { coinType: 0n, exists: true },
          { coinType: 1n, exists: false },
        ],
      };
      const { dedicatedResolver } = await F.namechain.setupName(kp);
      await dedicatedResolver.write.setAddr([0n, dummySelector]);
      await dedicatedResolver.write.setAddr([COIN_TYPE_DEFAULT, testAddress]);
      await sync();
      const bundle = bundleCalls(makeResolutions(kp));
      const [answer] = await F.mainnetV2.universalResolver.read.resolve([
        dnsEncodeName(kp.name),
        bundle.call,
      ]);
      bundle.expect(answer);
    });
    it("addr() w/fallback", async () => {
      const F = await loadFixture();
      const kp: KnownProfile = {
        name: testNames[0],
        addresses: [
          { coinType: COIN_TYPE_ETH, value: testAddress },
          { coinType: COIN_TYPE_DEFAULT, value: testAddress },
          { coinType: COIN_TYPE_DEFAULT | 1n, value: testAddress },
          { coinType: 0n, value: "0x" },
        ],
      };
      const { dedicatedResolver } = await F.namechain.setupName(kp);
      await dedicatedResolver.write.setAddr([COIN_TYPE_DEFAULT, testAddress]);
      await sync();
      const bundle = bundleCalls(makeResolutions(kp));
      const [answer] = await F.mainnetV2.universalResolver.read.resolve([
        dnsEncodeName(kp.name),
        bundle.call,
      ]);
      bundle.expect(answer);
    });
    describe("ABI()", () => {
      const kp: KnownProfile = {
        name: testNames[0],
        abis: [
          { contentType: 0n, value: "0x" },
          { contentType: 1n << 0n, value: "0x11" },
          { contentType: 1n << 3n, value: "0x8888" },
        ],
      };
      const [nul, ty1, ty8] = makeResolutions(kp);
      for (const [contentTypes, res] of [
        [[0], ty1],
        [[3], ty8],
        [[0, 3], ty1],
        [[1, 2, 3], ty8],
        [[], nul],
        [[2, 5], nul],
        [[255], nul],
      ] as const) {
        it(`contentTypes = [${contentTypes}]`, async () => {
          const F = await loadFixture();
          const { dedicatedResolver } = await F.namechain.setupName(kp);
          await dedicatedResolver.write.multicall([
            [ty1.writeDedicated, ty8.writeDedicated],
          ]);
          await sync();
          const [answer] = await F.mainnetV2.universalResolver.read.resolve([
            dnsEncodeName(kp.name),
            encodeFunctionData({
              abi: PROFILE_ABI,
              functionName: "ABI",
              args: [
                namehash(kp.name),
                contentTypes.reduce((a, x) => a | (1n << BigInt(x)), 0n),
              ],
            }),
          ]);
          res.expect(answer);
        });
      }
    });
    describe("multicall", () => {
      const resolutions = makeResolutions(kp);
      for (let n = 0; n <= resolutions.length; n++) {
        it(`calls = ${n}`, async () => {
          const F = await loadFixture();
          const { dedicatedResolver } = await F.namechain.setupName(kp);
          const bundle = bundleCalls(resolutions.slice(0, n));
          await F.namechain.walletClient.sendTransaction({
            to: dedicatedResolver.address,
            data: bundle.writeDedicated,
          });
          await sync();
          const [answer, resolver] =
            await F.mainnetV2.universalResolver.read.resolve([
              dnsEncodeName(kp.name),
              bundle.call,
            ]);
          expectVar({ resolver }).toEqualAddress(F.ethTLDResolver.address);
          bundle.expect(answer);
        });
      }
    });
    it("too many calls", async () => {
      const F = await loadFixture();
      const max = 10;
      const kp: KnownProfile = {
        name: testNames[0],
        addresses: [{ coinType: COIN_TYPE_ETH, value: testAddress }], // 1 proof
      };
      try {
        F.gateway.rollup.configure = (c) => {
          c.prover.maxUniqueProofs = 1 + max;
        };
        const [call] = makeResolutions(kp);
        const { dedicatedResolver } = await F.namechain.setupName(kp);
        await F.namechain.walletClient.sendTransaction({
          to: dedicatedResolver.address,
          data: call.writeDedicated,
        });
        await sync();
        const calls = Array.from({ length: max }, () => call);
        const bundle = bundleCalls(calls);
        const answer = await F.ethTLDResolver.read.resolve([
          dnsEncodeName(kp.name),
          bundle.call,
        ]);
        bundle.expect(answer);
        // TODO: UncheckedRollup doesn't respect maxUniqueProofs
        // TODO: fix after Urg adds callback error propagation
        // await expect(F.ethTLDResolver.read.resolve([
        //   dnsEncodeName(kp.name),
        //   bundleCalls([...calls, call]).call,
        // ])).toBeReverted();
      } finally {
        F.gateway.rollup.configure = undefined;
      }
    });
    it("every multicall failed", async () => {
      const kp: KnownProfile = {
        name: testNames[0],
        errors: Array.from({ length: 2 }, (_, i) => {
          const call = toHex(i, { size: 4 });
          return {
            call,
            answer: encodeErrorResult({
              abi: parseAbi(["error UnsupportedResolverProfile(bytes4)"]),
              args: [call],
            }),
          };
        }),
      };
      const F = await loadFixture();
      const bundle = bundleCalls(makeResolutions(kp));
      await sync();
      const [answer] = await F.mainnetV2.universalResolver.read.resolve([
        dnsEncodeName(kp.name),
        bundle.call,
      ]);
      bundle.expect(answer);
    });
  });

  describe("limits", () => {
    const maxProofs = 64; // likely gateway constraint

    // fixed size: addr(), pubkey(), hasAddr(), interfaceImplementer()
    // bytes-like: text(*), addr(*), contenthash()
    // complex: ABI()

    for (const name of testNames) {
      // see: RegistryDatastore.test.ts
      // to target exact resolver of "x.y.eth"
      // 1. AccountProof(registry)
      // 2. for each label:
      //    a. StorageProof(label's registry)
      //    b. StorageProof(label's resolver)
      // 3. AccountProof(resolver)
      // => 1 + 2*(n-1) + 1 = 2*n
      const lookupProofs = 2 * splitName(name).length;
      const proofBudget = maxProofs - lookupProofs; // remaining

      describe(`${name} = ${proofBudget}/${maxProofs}`, () => {
        it("bytes", async () => {
          const F = await loadFixture();
          const { dedicatedResolver } = await F.namechain.setupName({ name });
          F.gateway.rollup.configure = (c) => {
            c.prover.maxUniqueProofs = maxProofs;
            c.prover.maxProvableBytes = maxProofs << 5;
          };
          await run(0);
          await expect(run(1)).rejects.toThrow();
          async function run(extra: number) {
            const kp: KnownProfile = {
              name,
              contenthash: {
                value: bytesToHex(
                  new Uint8Array(((proofBudget - 1) << 5) + extra), // -1 for bytes.length
                ),
              },
            };
            const [res] = makeResolutions(kp);
            await F.namechain.walletClient.sendTransaction({
              to: dedicatedResolver.address,
              data: res.writeDedicated,
            });
            await sync();
            return F.mainnetV2.universalResolver.read
              .resolve([dnsEncodeName(kp.name), res.call])
              .then(([answer]) => res.expect(answer));
          }
        });

        it("ABI()", async () => {
          const F = await loadFixture();
          await F.namechain.setupName({ name });
          F.gateway.rollup.configure = (c) => {
            c.prover.maxUniqueProofs = maxProofs;
            c.prover.maxProvableBytes = maxProofs << 5;
            c.prover.maxStackSize = Infinity;
          };
          await run(0);
          await expect(run(1)).rejects.toThrow();
          async function run(extra: number) {
            await sync();
            return F.mainnetV2.universalResolver.read.resolve([
              dnsEncodeName(name),
              encodeFunctionData({
                abi: PROFILE_ABI,
                functionName: "ABI",
                args: [
                  namehash(name),
                  (1n << BigInt(proofBudget + extra)) - 1n,
                ],
              }),
            ]);
          }
        });
      });
    }
  });
});
