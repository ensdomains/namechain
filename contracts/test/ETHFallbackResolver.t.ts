import hre from "hardhat";
import {
  loadFixture,
  mine,
} from "@nomicfoundation/hardhat-toolbox-viem/network-helpers.js";
import { shouldSupportInterfaces } from "@ensdomains/hardhat-chai-matchers-viem/behaviour";
import {
  concat,
  encodeErrorResult,
  encodeFunctionData,
  keccak256,
  labelhash,
  namehash,
  parseAbi,
  toHex,
} from "viem";
import { expect } from "chai";
import { deployV2Fixture } from "./fixtures/deployV2Fixture.js";
import { deployV1Fixture } from "./fixtures/deployV1Fixture.js";
import { deployArtifact } from "./fixtures/deployArtifact.js";
import { urgArtifact } from "./fixtures/externalArtifacts.js";
import { Gateway } from "../lib/unruggable-gateways/src/gateway.js";
import { UncheckedRollup } from "../lib/unruggable-gateways/src/UncheckedRollup.js";
import { dnsEncodeName, expectVar, getLabelAt } from "./utils/utils.js";
import { serve } from "@namestone/ezccip/serve";
import { BrowserProvider } from "ethers/providers";
import {
  type KnownProfile,
  type KnownResolution,
  bundleCalls,
  makeResolutionsV1,
  makeResolutionsV2,
  COIN_TYPE_ETH,
  EVM_BIT,
} from "./utils/resolutions.js";

async function fixture() {
  const mainnetV1 = await deployV1Fixture(true); // CCIP on UR
  const mainnetV2 = await deployV2Fixture(true); // CCIP on UR
  const namechain = await deployV2Fixture();
  const gateway = new Gateway(
    new UncheckedRollup(new BrowserProvider(hre.network.provider)),
  );
  gateway.disableCache();
  const ccip = await serve(gateway, { protocol: "raw", log: false }); // enable to see gateway calls
  after(ccip.shutdown);
  const GatewayVM = await deployArtifact({ file: urgArtifact("GatewayVM") });
  const verifierAddress = await deployArtifact({
    file: urgArtifact("UncheckedVerifier"),
    args: [[ccip.endpoint]],
    libs: { GatewayVM },
  });
  const ethResolver = await mainnetV2.deploySingleNameResolver({
    owner: mainnetV2.walletClient.account.address,
  });
  const burnAddressV1 = "0x000000000000000000000000000000000000FadE";
  const ethFallbackResolver = await hre.viem.deployContract(
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
    {
      client: { public: mainnetV2.publicClient }, // CCIP on EFR
    },
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

const dummySelector = "0x12345678";
const testAddress = "0x8000000000000000000000000000000000000001";
const testNames = ["test.eth", "a.b.c.test.eth"];

describe("ETHFallbackResolver", () => {
  shouldSupportInterfaces({
    contract: () => loadFixture(fixture).then((F) => F.ethFallbackResolver),
    interfaces: ["IERC165", "IExtendedResolver"],
  });

  it("eth", async () => {
    const F = await loadFixture(fixture);
    const kp: KnownProfile = {
      name: "eth",
      addresses: [{ coinType: COIN_TYPE_ETH, value: testAddress }],
    };
    const [res] = makeResolutionsV2(kp);
    await F.ethResolver.write.multicall([[res.write]]);
    const [answer, resolver] = await F.mainnetV2.universalResolver.read.resolve(
      [dnsEncodeName(kp.name), res.call],
    );
    expectVar({ resolver }).toEqualAddress(F.ethFallbackResolver.address);
    res.expect(answer);
  });

  describe("unregistered", () => {
    for (const name of testNames) {
      it(name, async () => {
        const F = await loadFixture(fixture);
        const [res] = makeResolutionsV2({
          name,
          addresses: [{ coinType: COIN_TYPE_ETH, value: testAddress }],
        });
        await expect(F.mainnetV1.universalResolver)
          .read("resolve", [dnsEncodeName(name), res.call])
          .toBeRevertedWithCustomError("ResolverNotFound");
        // the errors are different because:
        // V1: requireResolver() fails
        // V2: gateway to namechain, no resolver found
        await expect(F.mainnetV2.universalResolver)
          .read("resolve", [dnsEncodeName(name), res.call])
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
        const F = await loadFixture(fixture);
        const kp: KnownProfile = {
          name,
          addresses: [{ coinType: COIN_TYPE_ETH, value: testAddress }],
        };
        const [res] = makeResolutionsV1(kp);
        await F.mainnetV1.setupName(kp.name);
        await F.mainnetV1.walletClient.sendTransaction({
          to: F.mainnetV1.ownedResolver.address,
          data: res.write, // V1 OwnedResolver lacks multicall()
        });
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
        const F = await loadFixture(fixture);
        const kp: KnownProfile = {
          name,
          addresses: [{ coinType: COIN_TYPE_ETH, value: testAddress }],
        };
        const [res] = makeResolutionsV2(kp);
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
        await F.namechain.setupName(kp);
        await F.namechain.singleNameResolver.write.multicall([[res.write]]);
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
        const F = await loadFixture(fixture);
        const kp: KnownProfile = {
          name,
          addresses: [{ coinType: COIN_TYPE_ETH, value: testAddress }],
        };
        await F.mainnetV2.setupName(kp);
        const [res] = makeResolutionsV2(kp);
        await F.mainnetV2.singleNameResolver.write.multicall([[res.write]]);
        const [answer, resolver] =
          await F.mainnetV2.universalResolver.read.resolve([
            dnsEncodeName(kp.name),
            res.call,
          ]);
        expectVar({ resolver }).toEqualAddress(
          F.mainnetV2.singleNameResolver.address,
        );
        res.expect(answer);
      });
    }
  });

  describe("registered on Namechain", () => {
    for (const name of testNames) {
      it(name, async () => {
        const F = await loadFixture(fixture);
        const kp: KnownProfile = {
          name,
          addresses: [{ coinType: COIN_TYPE_ETH, value: testAddress }],
        };
        await F.namechain.setupName(kp);
        const [res] = makeResolutionsV2(kp);
        await F.namechain.singleNameResolver.write.multicall([[res.write]]);
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
        const F = await loadFixture(fixture);
        const kp: KnownProfile = {
          name,
          addresses: [{ coinType: COIN_TYPE_ETH, value: testAddress }],
        };
        const interval = 10n;
        const { timestamp } = await F.namechain.publicClient.getBlock();
        await F.namechain.setupName({
          name: kp.name,
          expiry: timestamp + interval,
        });
        const [res] = makeResolutionsV2(kp);
        await F.namechain.singleNameResolver.write.multicall([[res.write]]);
        const answer = await F.ethFallbackResolver.read.resolve([
          dnsEncodeName(kp.name),
          res.call,
        ]);
        res.expect(answer);
        await mine(2, { interval }); // wait for the name to expire
        await expect(F.ethFallbackResolver)
          .read("resolve", [dnsEncodeName(kp.name), res.call])
          .toBeRevertedWithCustomError("UnreachableName");
      });
    }
  });

  describe("profile support", () => {
    const kp: KnownProfile = {
      name: testNames[0],
      primary: { value: testNames[0] },
      addresses: [
        { coinType: COIN_TYPE_ETH, value: testAddress },
        { coinType: 1n | EVM_BIT, value: testAddress },
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
      const F = await loadFixture(fixture);
      await expect(F.mainnetV2.universalResolver)
        .read("resolve", [dnsEncodeName(kp.name), dummySelector])
        .toBeRevertedWithCustomError("UnsupportedResolverProfile")
        .withArgs(dummySelector);
    });
    for (const res of makeResolutionsV2(kp)) {
      it(res.desc, async () => {
        const F = await loadFixture(fixture);
        await F.namechain.setupName(kp);
        await F.namechain.singleNameResolver.write.multicall([[res.write]]);
        const [answer, resolver] =
          await F.mainnetV2.universalResolver.read.resolve([
            dnsEncodeName(kp.name),
            res.call,
          ]);
        expectVar({ resolver }).toEqualAddress(F.ethFallbackResolver.address);
        res.expect(answer);
      });
    }
    it("multiple ABI contentTypes", async () => {
      const kp: KnownProfile = {
        name: testNames[0],
        abis: [
          { contentType: 0n, value: "0x" },
          { contentType: 1n, value: "0x11" },
          { contentType: 8n, value: "0x8888" },
        ],
      };
      const [nul, ty1, ty8] = makeResolutionsV2(kp);
      const F = await loadFixture(fixture);
      await F.namechain.setupName(kp);
      await F.namechain.singleNameResolver.write.multicall([[ty1.write, ty8.write]]);
      await check(1n, ty1);
      await check(8n, ty8);
      await check(1n | 8n, ty1);
      await check(2n | 4n | 8n, ty8);
      await check(1n << 1n, nul);
      await check(1n << 255n, nul);
      async function check(contentType: bigint, res: KnownResolution) {
        const [answer] = await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(kp.name),
          encodeFunctionData({
            abi: F.namechain.singleNameResolver.abi,
            functionName: "ABI",
            args: [namehash(kp.name), contentType],
          }),
        ]);
        res.desc = `ABI(${contentType})`;
        res.expect(answer);
      }
    });
    it(`multicall()`, async () => {
      const F = await loadFixture(fixture);
      await F.namechain.setupName(kp);
      await F.namechain.singleNameResolver.write.multicall([
        makeResolutionsV2(kp).map((x) => x.write),
      ]);
      const bundle = bundleCalls(makeResolutionsV2({ ...kp, errors }));
      const [answer, resolver] =
        await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(kp.name),
          bundle.call,
        ]);
      expectVar({ resolver }).toEqualAddress(F.ethFallbackResolver.address);
      bundle.expect(answer);
    });
    it("resolve(multicall)", async () => {
      const F = await loadFixture(fixture);
      await F.namechain.setupName(kp);
      await F.namechain.singleNameResolver.write.multicall([
        makeResolutionsV2(kp).map((x) => x.write),
      ]);
      const bundle = bundleCalls(makeResolutionsV2({ ...kp, errors }));
      // the UR doesn't yet support direct resolve(multicall)
      // so we explicitly call the resolver until this is possible
      const answer = await F.ethFallbackResolver.read.resolve([
        dnsEncodeName(kp.name),
        bundle.call,
      ]);
      bundle.expect(answer);
    });
    it("zero multicalls", async () => {
      const kp: KnownProfile = { name: testNames[0] };
      const F = await loadFixture(fixture);
      const bundle = bundleCalls(makeResolutionsV2(kp));
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
      const F = await loadFixture(fixture);
      const bundle = bundleCalls(makeResolutionsV2(kp));
      const [answer] = await F.mainnetV2.universalResolver.read.resolve([
        dnsEncodeName(kp.name),
        bundle.call,
      ]);
      bundle.expect(answer);
    });
  });
});
