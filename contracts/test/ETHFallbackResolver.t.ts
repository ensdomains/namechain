import hre from "hardhat";
import {
  loadFixture,
  mine,
} from "@nomicfoundation/hardhat-toolbox-viem/network-helpers.js";
import { shouldSupportInterfaces } from "@ensdomains/hardhat-chai-matchers-viem/behaviour";
import {
  encodeErrorResult,
  encodeFunctionData,
  keccak256,
  namehash,
  parseAbi,
  toHex,
} from "viem";
import { expect } from "chai";
import { deployV2Fixture } from "./fixtures/deployV2Fixture.js";
import { deployV1Fixture } from "./fixtures/deployV1Fixture.js";
import { launchBatchGateway } from "./utils/localBatchGateway.js";
import { deployArtifact } from "./fixtures/deployArtifact.js";
import { urgArtifact } from "./fixtures/externalArtifacts.js";
import { UncheckedRollup } from "../lib/unruggable-gateways/src/UncheckedRollup.js";
import { Gateway } from "../lib/unruggable-gateways/src/gateway.js";
import { dnsEncodeName, labelhashUint256 } from "./utils/utils.js";
import { serve } from "@namestone/ezccip/serve";
import { BrowserProvider } from "ethers/providers";
import {
  type KnownProfile,
  bundleCalls,
  makeResolutions,
  COIN_TYPE_ETH,
  EVM_BIT,
} from "./utils/resolutions.js";

async function fixture() {
  const batchGateways = await launchBatchGateway();
  const mainnetV1 = await deployV1Fixture(batchGateways); // CCIP on UR
  const mainnetV2 = await deployV2Fixture(batchGateways); // CCIP on UR
  const namechain = await deployV2Fixture();
  const gateway = new Gateway(
    new UncheckedRollup(new BrowserProvider(hre.network.provider)),
  );
  gateway.disableCache();
  const ccip = await serve(gateway, { protocol: "raw", log: false });
  after(ccip.shutdown);
  const GatewayVM = await deployArtifact({
    file: urgArtifact("GatewayVM"),
  });
  const verifierAddress = await deployArtifact({
    file: urgArtifact("UncheckedVerifier"),
    args: [[ccip.endpoint]],
    libs: { GatewayVM },
  });
  const burnAddressV1 = "0x000000000000000000000000000000000000FadE";
  const ethFallbackResolver = await hre.viem.deployContract(
    "ETHFallbackResolver",
    [
      mainnetV1.ethRegistrar.address,
      mainnetV1.universalResolver.address,
      burnAddressV1,
      verifierAddress,
      namechain.datastore.address,
      namechain.ethRegistry.address,
    ],
    {
      client: { public: mainnetV2.publicClient }, // CCIP on EFR
    },
  );
  await mainnetV2.rootRegistry.write.setResolver([
    labelhashUint256("eth"),
    ethFallbackResolver.address,
  ]);
  return {
    ethFallbackResolver,
    mainnetV1,
    burnAddressV1,
    mainnetV2,
    namechain,
  } as const;
}

const dummySelector = "0x12345678";
const testAddress = "0x8000000000000000000000000000000000000001";

describe("ETHFallbackResolver", () => {
  shouldSupportInterfaces({
    contract: () => loadFixture(fixture).then((F) => F.ethFallbackResolver),
    interfaces: ["IERC165", "IExtendedResolver"],
  });

  describe("unregistered", () => {
    for (const name of ["test.eth", "a.b.c.test.eth"]) {
      it(name, async () => {
        const F = await loadFixture(fixture);
        const [res] = makeResolutions({
          name,
          addresses: [
            {
              coinType: COIN_TYPE_ETH,
              value: testAddress,
            },
          ],
        });
        await expect(F.mainnetV1.universalResolver)
          .read("resolve", [dnsEncodeName(name), res.call])
          .toBeRevertedWithCustomError("ResolverNotFound");
        // the errors are different because:
        // v1: requireResolver() fails
        // v2: gateway to namechain, no resolver found
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

  describe("registered on V1", () => {
    it("eth", async () => {
      const F = await loadFixture(fixture);
      const kp: KnownProfile = {
        name: "eth",
        addresses: [
          {
            coinType: COIN_TYPE_ETH,
            value: F.mainnetV1.ethRegistrar.address,
          },
        ],
      };
      const [res] = makeResolutions(kp);
      const [answer, resolver] =
        await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(kp.name),
          res.call,
        ]);
      expect(resolver).toEqualAddress(F.ethFallbackResolver.address);
      res.expect(answer);
    });
    for (const name of ["boomer.eth", "a.b.c.boomer.eth"]) {
      it(name, async () => {
        const F = await loadFixture(fixture);
        const kp: KnownProfile = {
          name,
          addresses: [
            {
              coinType: COIN_TYPE_ETH,
              value: testAddress,
            },
          ],
        };
        const [res] = makeResolutions(kp);
        await F.mainnetV1.setupName(kp.name);
        // await F.mainnetV1.ownedResolver.write.multicall([res.write]);
        await F.mainnetV1.walletClient.sendTransaction({
          to: F.mainnetV1.ownedResolver.address,
          data: res.write,
        });
        const [answer, resolver] =
          await F.mainnetV2.universalResolver.read.resolve([
            dnsEncodeName(kp.name),
            res.call,
          ]);
        expect(resolver).toEqualAddress(F.ethFallbackResolver.address);
        res.expect(answer);
      });
    }
  });

  describe("migrated from V1", () => {
    const label = "burned";
    for (const name of [`${label}.eth`, `a.b.c.${label}.eth`]) {
      it(name, async () => {
        const F = await loadFixture(fixture);
        const kp: KnownProfile = {
          name,
          addresses: [
            {
              coinType: COIN_TYPE_ETH,
              value: testAddress,
            },
          ],
        };
        const [res] = makeResolutions(kp);
        await F.mainnetV1.setupName(kp.name);
        await F.mainnetV1.ethRegistrar.write.safeTransferFrom([
          F.mainnetV1.walletClient.account.address,
          F.burnAddressV1,
          labelhashUint256(label),
        ]);
        const available = await F.mainnetV1.ethRegistrar.read.available([
          labelhashUint256(label),
        ]);
        expect(available).toStrictEqual(false);
        await F.namechain.setupName(kp);
        await F.namechain.ownedResolver.write.multicall([[res.write]]);
        const [answer, resolver] =
          await F.mainnetV2.universalResolver.read.resolve([
            dnsEncodeName(kp.name),
            res.call,
          ]);
        expect(resolver).toEqualAddress(F.ethFallbackResolver.address);
        res.expect(answer);
      });
    }
  });

  describe("registered on mainnet", () => {
    for (const name of ["test.eth", "a.b.c.test.eth"]) {
      it(name, async () => {
        const F = await loadFixture(fixture);
        const kp: KnownProfile = {
          name,
          addresses: [
            {
              coinType: COIN_TYPE_ETH,
              value: testAddress,
            },
          ],
        };
        await F.mainnetV2.setupName(kp);
        const [res] = makeResolutions(kp);
        await F.mainnetV2.ownedResolver.write.multicall([[res.write]]);
        const [answer, resolver] =
          await F.mainnetV2.universalResolver.read.resolve([
            dnsEncodeName(kp.name),
            res.call,
          ]);
        expect(resolver).toEqualAddress(F.mainnetV2.ownedResolver.address);
        res.expect(answer);
      });
    }
  });

  describe("registered on namechain", () => {
    for (const name of ["test.eth", "a.b.c.test.eth"]) {
      it(name, async () => {
        const F = await loadFixture(fixture);
        const kp: KnownProfile = {
          name,
          addresses: [
            {
              coinType: COIN_TYPE_ETH,
              value: testAddress,
            },
          ],
        };
        await F.namechain.setupName(kp);
        const [res] = makeResolutions(kp);
        await F.namechain.ownedResolver.write.multicall([[res.write]]);
        const [answer, resolver] =
          await F.mainnetV2.universalResolver.read.resolve([
            dnsEncodeName(kp.name),
            res.call,
          ]);
        expect(resolver).toEqualAddress(F.ethFallbackResolver.address);
        res.expect(answer);
      });
    }
  });

  describe("expired", () => {
    for (const name of ["test.eth", "a.b.c.test.eth"]) {
      it(name, async () => {
        const F = await loadFixture(fixture);
        const kp: KnownProfile = {
          name,
          addresses: [
            {
              coinType: COIN_TYPE_ETH,
              value: testAddress,
            },
          ],
        };
        const interval = 10n;
        const { timestamp } = await F.namechain.publicClient.getBlock();
        await F.namechain.setupName({
          name: kp.name,
          expiry: timestamp + interval,
        });
        const [res] = makeResolutions(kp);
        await F.namechain.ownedResolver.write.multicall([[res.write]]);
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
      name: "test.eth",
      addresses: [
        {
          coinType: COIN_TYPE_ETH,
          value: testAddress,
        },
        {
          coinType: 1n | EVM_BIT,
          value: testAddress,
        },
        {
          coinType: 2n,
          value: "0x1234",
        },
      ],
      texts: [{ key: "url", value: "https://ens.domains" }],
      contenthash: { value: "0xabcdef" },
      pubkey: {
        x: keccak256("0x1"),
        y: keccak256("0x2"),
      },
      primary: { value: "test.eth" },
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
        .read("resolve", [dnsEncodeName("test.eth"), dummySelector])
        .toBeRevertedWithCustomError("UnsupportedResolverProfile")
        .withArgs(dummySelector);
    });
    it("recordVersions", async () => {
      const F = await loadFixture(fixture);
      await F.namechain.setupName(kp);
      const call = encodeFunctionData({
        abi: F.namechain.ownedResolver.abi,
        functionName: "recordVersions",
        args: [namehash(kp.name)],
      });
      const [answer0] = await F.mainnetV2.universalResolver.read.resolve([
        dnsEncodeName(kp.name),
        call,
      ]);
      expect(answer0, "0").toStrictEqual(toHex(0, { size: 32 }));
      await F.namechain.ownedResolver.write.clearRecords([namehash(kp.name)]);
      const [answer1] = await F.mainnetV2.universalResolver.read.resolve([
        dnsEncodeName(kp.name),
        call,
      ]);
      expect(answer1, "1").toStrictEqual(toHex(1, { size: 32 }));
    });
    for (const res of makeResolutions(kp)) {
      it(res.desc, async () => {
        const F = await loadFixture(fixture);
        await F.namechain.setupName(kp);
        await F.namechain.ownedResolver.write.multicall([[res.write]]);
        const [answer, resolver] =
          await F.mainnetV2.universalResolver.read.resolve([
            dnsEncodeName(kp.name),
            res.call,
          ]);
        expect(resolver).toEqualAddress(F.ethFallbackResolver.address);
        res.expect(answer);
      });
    }
    it(`multicall()`, async () => {
      const F = await loadFixture(fixture);
      await F.namechain.setupName(kp);
      await F.namechain.ownedResolver.write.multicall([
        makeResolutions(kp).map((x) => x.write),
      ]);
      const bundle = bundleCalls(makeResolutions({ ...kp, errors }));
      const [answer, resolver] =
        await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(kp.name),
          bundle.call,
        ]);
      expect(resolver).toEqualAddress(F.ethFallbackResolver.address);
      bundle.expect(answer);
    });
    it("resolve(multicall)", async () => {
      const F = await loadFixture(fixture);
      await F.namechain.setupName(kp);
      await F.namechain.ownedResolver.write.multicall([
        makeResolutions(kp).map((x) => x.write),
      ]);
      const bundle = bundleCalls(makeResolutions({ ...kp, errors }));
      const answer = await F.ethFallbackResolver.read.resolve([
        dnsEncodeName(kp.name),
        bundle.call,
      ]);
      bundle.expect(answer);
    });
  });
});
