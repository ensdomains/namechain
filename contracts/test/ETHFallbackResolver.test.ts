import hre from "hardhat";
import { shouldSupportInterfaces } from "@ensdomains/hardhat-chai-matchers-viem/behaviour";
import { expect } from "chai";
import { afterEach, afterAll, describe, it } from "vitest";
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
import { InteractiveRollup } from "../lib/unruggable-gateways/src/InteractiveRollup.js";
import { EthProver } from "../lib/unruggable-gateways/src/eth/EthProver.js";
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
import { injectRPCCounter } from "./utils/hardhat.js";
import { FEATURES } from "./utils/features.js";

const chain1 = injectRPCCounter(await hre.network.connect());
const chain2 = injectRPCCounter(await hre.network.connect());
const chains = [chain1, chain2];

function namechainFixture() {
  return deployV2Fixture(chain2);
}

async function fixture() {
  const mainnetV1 = await deployV1Fixture(chain1, true); // CCIP on UR
  const mainnetV2 = await deployV2Fixture(chain1, true); // CCIP on UR
  const namechain = await chain2.networkHelpers.loadFixture(namechainFixture);

  const GatewayVM = await deployArtifact(mainnetV2.walletClient, {
    file: urgArtifact("GatewayVM"),
  });
  const hooksAddress = await deployArtifact(mainnetV2.walletClient, {
    file: urgArtifact("EthVerifierHooks"),
  });
  const verifierAddress = await deployArtifact(mainnetV2.walletClient, {
    file: urgArtifact("InteractiveVerifier"),
    args: [[], 1000, hooksAddress],
    libs: { GatewayVM },
  });
  const gateway = new Gateway(
    new InteractiveRollup(
      {
        provider1: new BrowserProvider(chain1.provider),
        provider2: new BrowserProvider(chain2.provider),
      },
      verifierAddress,
      EthProver,
    ),
  );
  gateway.disableCache();
  const ccip = await serve(gateway, { protocol: "raw", log: false }); // enable to see gateway calls
  afterAll(ccip.shutdown);

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
    sync,
  } as const;
  async function sync() {
    const n1 = chain1.count;
    const n2 = chain2.count;
    const [last, block1, block2] = await Promise.all([
      gateway.rollup.fetchLatestCommitIndex(),
      mainnetV2.publicClient.getBlock(),
      namechain.publicClient.getBlock(),
    ]);
    if (block2.timestamp > block1.timestamp) {
      await chain1.networkHelpers.time.setNextBlockTimestamp(block2.timestamp);
    }
    if (block2.number > last) {
      const [wallet] = await chain1.viem.getWalletClients();
      await wallet.writeContract({
        address: verifierAddress,
        abi: parseAbi(["function setStateRoot(uint256, bytes32)"]),
        functionName: 'setStateRoot',
        args: [block2.number, block2.stateRoot],
      });
    } else {
      await chain1.networkHelpers.mine(1);
    }
    chain1.count = n1;
    chain2.count = n2;
  }
}

const loadFixture = async () => {
  await chain2.networkHelpers.loadFixture(namechainFixture);
  return chain1.networkHelpers.loadFixture(fixture);
};

const dummySelector = "0x12345678";
const testAddress = "0x8000000000000000000000000000000000000001";
const testNames = ["test.eth", "a.b.c.test.eth"];

describe("ETHFallbackResolver", () => {
  const rpcs: Record<string, number[]> = {};
  afterEach(({ expect: { getState } }) => {
    rpcs[getState().currentTestName!] = chains.map((x) => x.reset());
  });
  // enable to print rpc call counts:
  // afterAll(() => console.log(rpcs));

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

  it("eth", async () => {
    const F = await loadFixture();
    const kp: KnownProfile = {
      name: "eth",
      addresses: [{ coinType: COIN_TYPE_ETH, value: testAddress }],
    };
    const [res] = makeResolutions(kp);
    await F.ethResolver.write.multicall([[res.writeDedicated]]);
    await F.sync();
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
        await F.sync();
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
        await F.sync();
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
        await F.sync();
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
        await F.sync();
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
        await F.sync();
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
        await F.sync();
        const { timestamp } = await F.namechain.publicClient.getBlock();
        await F.namechain.setupName({
          name: kp.name,
          expiry: timestamp + interval,
        });
        const [res] = makeResolutions(kp);
        await F.namechain.dedicatedResolver.write.multicall([
          [res.writeDedicated],
        ]);
        await F.sync();
        const answer = await F.ethFallbackResolver.read.resolve([
          dnsEncodeName(kp.name),
          res.call,
        ]);
        res.expect(answer);
        await chain2.networkHelpers.mine(2, { interval }); // wait for the name to expire
        await F.sync();
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
      await F.sync();
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
        await F.sync();
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
        await F.sync();
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
      await F.sync();
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
        await F.sync();
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
    });
    it(`multicall()`, async () => {
      const F = await loadFixture();
      await F.namechain.setupName(kp);
      await F.namechain.dedicatedResolver.write.multicall([
        makeResolutions(kp).map((x) => x.writeDedicated),
      ]);
      const bundle = bundleCalls(makeResolutions({ ...kp, errors }));
      await F.sync();
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
      await F.sync();
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
      await F.sync();
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
      await F.sync();
      const [answer] = await F.mainnetV2.universalResolver.read.resolve([
        dnsEncodeName(kp.name),
        bundle.call,
      ]);
      bundle.expect(answer);
    });
  });
});
