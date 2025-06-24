import hre from "hardhat";
import { shouldSupportInterfaces } from "@ensdomains/hardhat-chai-matchers-viem/behaviour";
import { expect } from "chai";
import { afterEach, afterAll, describe, it, assert } from "vitest";
import { readFileSync } from "node:fs";
import {
  concat,
  decodeFunctionResult,
  encodeErrorResult,
  encodeFunctionData,
  keccak256,
  labelhash,
  namehash,
  parseAbi,
  toHex,
} from "viem";
import { BrowserProvider } from "ethers/providers";
import { serve } from "@namestone/ezccip/serve";
import { Gateway } from "../lib/unruggable-gateways/src/gateway.js";
import { UncheckedRollup } from "../lib/unruggable-gateways/src/UncheckedRollup.js";
import { deployArtifact } from "./fixtures/deployArtifact.js";
import { deployV1Fixture } from "./fixtures/deployV1Fixture.js";
import { deployV2Fixture } from "./fixtures/deployV2Fixture.js";
import { urgArtifact } from "./fixtures/externalArtifacts.js";
import {
  COIN_TYPE_ETH,
  COIN_TYPE_DEFAULT,
  type KnownProfile,
  type KnownResolution,
  bundleCalls,
  makeResolutions,
  shortCoin,
} from "./utils/resolutions.js";
import { dnsEncodeName, expectVar, getLabelAt } from "./utils/utils.js";
import { getRawArtifact, injectRPCCounter } from "./utils/hardhat.js";
import { FEATURES } from "./utils/features.js";

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
  const ccip = await serve(gateway, { protocol: "raw", log: false }); // enable to see gateway calls
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
  const ethResolver = await mainnetV2.deployDedicatedResolver({
    owner: mainnetV2.walletClient.account.address,
  });
  const burnAddressV1 = "0x000000000000000000000000000000000000FadE";
  const ethFallbackResolver = await chain1.viem.deployContract(
    "ETHFallbackResolver",
    [
      mainnetV1.ethRegistrar.address,
      mainnetV1.universalResolver.address,
      burnAddressV1,
      ethResolver.address,
      verifierAddress,
      namechain.datastore.address,
      namechain.ethRegistry.address,
    ],
    { client: { public: mainnetV2.publicClient } }, // CCIP on EFR
  );
  await mainnetV2.rootRegistry.write.setResolver([
    BigInt(labelhash("eth")),
    ethFallbackResolver.address,
  ]);
  return {
    ethFallbackResolver,
    ethResolver,
    mainnetV1,
    burnAddressV1,
    mainnetV2,
    namechain,
  } as const;
}

const loadFixture = async () => {
  await chain2.networkHelpers.loadFixture(namechainFixture);
  return chain1.networkHelpers.loadFixture(fixture);
};

const dummySelector = "0x12345678";
const testAddress = "0x8000000000000000000000000000000000000001";
const testNames = ["test.eth", "a.b.c.test.eth"];

describe("ETHFallbackResolver", () => {
  const rpcs: Record<string, any> = {};
  afterEach(({ expect: { getState } }) => {
    rpcs[getState().currentTestName!] = [
      chain1.counts.eth_call,
      chain2.counts.eth_call,
      chain2.counts.eth_getStorageAt,
    ].map((x) => x || 0);
    chain1.counts = {};
    chain2.counts = {};
  });
  // enable to print rpc call counts:
  //afterAll(() => console.log(rpcs));

  shouldSupportInterfaces({
    contract: () => loadFixture().then((F) => F.ethFallbackResolver),
    interfaces: ["IERC165", "IExtendedResolver", "IFeatureSupporter"],
  });

  it("supportsFeature: resolve(multicall)", async () => {
    const F = await loadFixture();
    await expect(
      F.ethFallbackResolver.read.supportsFeature([
        FEATURES.RESOLVER.RESOLVE_MULTICALL,
      ]),
    ).resolves.toStrictEqual(true);
  });

  describe("storage layout", { timeout: 30000 }, () => {
    describe("DedicatedResolver", () => {
      const code = readFileSync(
        new URL("../src/common/DedicatedResolverLayout.sol", import.meta.url),
        "utf8",
      );
      for (const match of code.matchAll(/constant (SLOT_\S+) = (\S+);/g)) {
        it(`${match[1]} = ${match[2]}`, async () => {
          const { storageLayout } = await getRawArtifact("DedicatedResolver");
          const label = match[1].slice(4).toLowerCase(); // "SLOT_ABC" => "_abc"
          const ref = storageLayout.storage.find((x) =>
            x.label.startsWith(label),
          );
          assert(ref?.slot === match[2]);
        });
      }
    });
    it("SLOT_RD_ENTRIES = 0", async () => {
      const {
        storageLayout: {
          storage: [{ slot, label }],
        },
      } = await getRawArtifact("RegistryDatastore");
      expectVar({ slot }).toStrictEqual("0");
      expectVar({ label }).toStrictEqual("entries");
    });
  });

  it("eth", async () => {
    const F = await loadFixture();
    const kp: KnownProfile = {
      name: "eth",
      addresses: [{ coinType: COIN_TYPE_ETH, value: testAddress }],
    };
    const [res] = makeResolutions(kp);
    await F.ethResolver.write.multicall([[res.writeDedicated]]);
    await sync();
    const [answer, resolver] = await F.mainnetV2.universalResolver.read.resolve(
      [dnsEncodeName(kp.name), res.call],
    );
    expectVar({ resolver }).toEqualAddress(F.ethFallbackResolver.address);
    res.expect(answer);
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
          .withArgs(
            encodeErrorResult({
              abi: F.ethFallbackResolver.abi,
              errorName: "UnreachableName",
              args: [dnsEncodeName(name)],
            }),
          );
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
        await F.mainnetV1.setupName(kp.name);
        await F.mainnetV1.walletClient.sendTransaction({
          to: F.mainnetV1.ownedResolver.address,
          data: res.write, // V1 OwnedResolver lacks multicall()
        });
        await sync();
        const [answer, resolver] =
          await F.mainnetV2.universalResolver.read.resolve([
            dnsEncodeName(kp.name),
            res.call,
          ]);
        expectVar({ resolver }).toEqualAddress(F.ethFallbackResolver.address);
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
        await F.mainnetV1.setupName(kp.name);
        const tokenId = BigInt(labelhash(getLabelAt(kp.name, -2)));
        await F.mainnetV1.ethRegistrar.write.safeTransferFrom([
          F.mainnetV1.walletClient.account.address,
          F.burnAddressV1,
          tokenId,
        ]);
        const available = await F.mainnetV1.ethRegistrar.read.available([
          tokenId,
        ]);
        expectVar({ available }).toStrictEqual(false);
        await F.namechain.setupName({ name });
        await F.namechain.dedicatedResolver.write.multicall([
          [res.writeDedicated],
        ]);
        await sync();
        const [answer, resolver] =
          await F.mainnetV2.universalResolver.read.resolve([
            dnsEncodeName(kp.name),
            res.call,
          ]);
        expectVar({ resolver }).toEqualAddress(F.ethFallbackResolver.address);
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
        await F.mainnetV2.setupName(kp);
        const [res] = makeResolutions(kp);
        await F.mainnetV2.dedicatedResolver.write.multicall([
          [res.writeDedicated],
        ]);
        await sync();
        const [answer, resolver] =
          await F.mainnetV2.universalResolver.read.resolve([
            dnsEncodeName(kp.name),
            res.call,
          ]);
        expectVar({ resolver }).toEqualAddress(
          F.mainnetV2.dedicatedResolver.address,
        );
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
        await F.namechain.setupName(kp);
        const [res] = makeResolutions(kp);
        await F.namechain.dedicatedResolver.write.multicall([
          [res.writeDedicated],
        ]);
        await sync();
        const [answer, resolver] =
          await F.mainnetV2.universalResolver.read.resolve([
            dnsEncodeName(kp.name),
            res.call,
          ]);
        expectVar({ resolver }).toEqualAddress(F.ethFallbackResolver.address);
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
        await F.namechain.setupName({
          name: kp.name,
          expiry: timestamp + interval,
        });
        const [res] = makeResolutions(kp);
        await F.namechain.dedicatedResolver.write.multicall([
          [res.writeDedicated],
        ]);
        await sync();
        const answer = await F.ethFallbackResolver.read.resolve([
          dnsEncodeName(kp.name),
          res.call,
        ]);
        res.expect(answer);
        await chain2.networkHelpers.mine(2, { interval }); // wait for the name to expire
        await sync();
        await expect(
          F.ethFallbackResolver.read.resolve([
            dnsEncodeName(kp.name),
            res.call,
          ]),
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
        //       abi: F.ethFallbackResolver.abi,
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
        { coinType: 1n | COIN_TYPE_DEFAULT, value: testAddress },
        { coinType: 2n, value: concat([keccak256("0x0"), "0x01"]) },
      ],
      texts: [{ key: "url", value: "https://ens.domains" }],
      contenthash: { value: concat([keccak256("0x1"), "0x01"]) },
      pubkey: { x: keccak256("0x2"), y: keccak256("0x3") },
      abis: [{ contentType: 8n, value: concat([keccak256("0x4"), "0x01"]) }],
      interfaces: [{ selector: dummySelector, value: testAddress }],
    };
    const errors: KnownProfile["errors"] = [
      {
        call: dummySelector,
        answer: encodeErrorResult({
          abi: parseAbi(["error UnsupportedResolverProfile(bytes4)"]),
          args: [dummySelector],
        }),
      },
    ];
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
        .withArgs(dummySelector);
    });
    for (const res of makeResolutions(kp)) {
      it(res.desc, async () => {
        const F = await loadFixture();
        await F.namechain.setupName(kp);
        await F.namechain.dedicatedResolver.write.multicall([
          [res.writeDedicated],
        ]);
        await sync();
        const [answer, resolver] =
          await F.mainnetV2.universalResolver.read.resolve([
            dnsEncodeName(kp.name),
            res.call,
          ]);
        expectVar({ resolver }).toEqualAddress(F.ethFallbackResolver.address);
        res.expect(answer);
      });
    }
    it("hasAddr()", async () => {
      const F = await loadFixture();
      const kp: KnownProfile = {
        name: testNames[0],
        addresses: [{ coinType: COIN_TYPE_DEFAULT, value: testAddress }],
      };
      await F.namechain.setupName(kp);
      const [res] = makeResolutions(kp);
      await F.namechain.dedicatedResolver.write.multicall([
        [res.writeDedicated],
      ]);
      await check(COIN_TYPE_DEFAULT, true);
      await check(COIN_TYPE_ETH, false);
      await check(0n, false);
      async function check(coinType: bigint, has: boolean) {
        await sync();
        const [data] = await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(kp.name),
          encodeFunctionData({
            abi: F.namechain.dedicatedResolver.abi,
            functionName: "hasAddr",
            args: [namehash(kp.name), coinType],
          }),
        ]);
        expect(
          decodeFunctionResult({
            abi: F.namechain.dedicatedResolver.abi,
            functionName: "hasAddr",
            data,
          }),
          shortCoin(coinType),
        ).toStrictEqual(has);
      }
    });
    it("addr() w/fallback", async () => {
      const F = await loadFixture();
      const kp: KnownProfile = {
        name: testNames[0],
        addresses: [
          { coinType: COIN_TYPE_DEFAULT, value: testAddress },
          { coinType: COIN_TYPE_ETH, value: testAddress },
          { coinType: COIN_TYPE_DEFAULT + 1n, value: testAddress },
        ],
      };
      await F.namechain.setupName(kp);
      const bundle = bundleCalls(makeResolutions(kp));
      await F.namechain.dedicatedResolver.write.multicall([
        [bundle.resolutions[0].writeDedicated], // only set default
      ]);
      await sync();
      const [answer] = await F.mainnetV2.universalResolver.read.resolve([
        dnsEncodeName(kp.name),
        bundle.call,
      ]);
      bundle.expect(answer);
    });
    it("multiple ABI contentTypes", async () => {
      const kp: KnownProfile = {
        name: testNames[0],
        abis: [
          { contentType: 0n, value: "0x" },
          { contentType: 1n, value: "0x11" },
          { contentType: 8n, value: "0x8888" },
        ],
      };
      const [nul, ty1, ty8] = makeResolutions(kp);
      const F = await loadFixture();
      await F.namechain.setupName(kp);
      await F.namechain.dedicatedResolver.write.multicall([
        [ty1.writeDedicated, ty8.writeDedicated],
      ]);
      await check(1n, ty1);
      await check(8n, ty8);
      await check(1n | 8n, ty1);
      await check(2n | 4n | 8n, ty8);
      await check(2n, nul);
      await check(1n << 255n, nul);
      async function check(contentTypes: bigint, res: KnownResolution) {
        await sync();
        const [answer] = await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(kp.name),
          encodeFunctionData({
            abi: parseAbi([
              "function ABI(bytes32, uint256 contentTypes) external view returns (uint256, bytes memory)",
            ]),
            functionName: "ABI",
            args: [namehash(kp.name), contentTypes],
          }),
        ]);
        res.desc = `ABI(${contentTypes})`;
        res.expect(answer);
      }
    }, { timeout: 20000 });
    it(`multicall()`, async () => {
      const F = await loadFixture();
      await F.namechain.setupName(kp);
      await F.namechain.dedicatedResolver.write.multicall([
        makeResolutions(kp).map((x) => x.writeDedicated),
      ]);
      const bundle = bundleCalls(makeResolutions({ ...kp, errors }));
      await sync();
      const [answer, resolver] =
        await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(kp.name),
          bundle.call,
        ]);
      expectVar({ resolver }).toEqualAddress(F.ethFallbackResolver.address);
      bundle.expect(answer);
    });
    it("resolve(multicall)", async () => {
      const F = await loadFixture();
      await F.namechain.setupName(kp);
      await F.namechain.dedicatedResolver.write.multicall([
        makeResolutions(kp).map((x) => x.writeDedicated),
      ]);
      const bundle = bundleCalls(makeResolutions({ ...kp, errors }));
      // the UR doesn't yet support direct resolve(multicall)
      // so we explicitly call the resolver until this is possible
      await sync();
      const answer = await F.ethFallbackResolver.read.resolve([
        dnsEncodeName(kp.name),
        bundle.call,
      ]);
      bundle.expect(answer);
    });
    it("zero multicalls", async () => {
      const kp: KnownProfile = { name: testNames[0] };
      const F = await loadFixture();
      const bundle = bundleCalls(makeResolutions(kp));
      await sync();
      const [answer] = await F.mainnetV2.universalResolver.read.resolve([
        dnsEncodeName(kp.name),
        bundle.call,
      ]);
      bundle.expect(answer);
    });
    it("every multicalls failed", async () => {
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
});
