import hre from "hardhat";
import {
  loadFixture,
  mine,
} from "@nomicfoundation/hardhat-toolbox-viem/network-helpers.js";
import { shouldSupportInterfaces } from "@ensdomains/hardhat-chai-matchers-viem/behaviour";
import { encodeErrorResult, parseAbi } from "viem";
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
  const mainnet = await deployV2Fixture(batchGateways); // CCIP on UR
  const namechain = await deployV2Fixture();
  const gateway = new Gateway(
    new UncheckedRollup(new BrowserProvider(hre.network.provider)),
  );
  gateway.disableCache();
  // beforeEach(() => {
  //   gateway.commitCacheMap.clear();
  //   gateway.latestCache.clear();
  //   gateway.callLRU.clear();
  // });
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
  const ethFallbackResolver = await hre.viem.deployContract(
    "ETHFallbackResolver",
    [
      mainnetV1.ethRegistrar.address,
      mainnetV1.universalResolver.address,
      namechain.datastore.address,
      namechain.ethRegistry.address,
      verifierAddress,
    ],
    {
      client: { public: mainnet.publicClient }, // CCIP on EFR
    },
  );
  await mainnet.rootRegistry.write.setResolver([
    labelhashUint256("eth"),
    ethFallbackResolver.address,
  ]);
  return {
    ethFallbackResolver,
    mainnet,
    mainnetV1,
    namechain,
  };
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
        await expect(F.mainnet.universalResolver)
          .read("resolve", [dnsEncodeName(name), res.call])
          .toBeRevertedWithCustomError("ResolverError");
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
      const [answer, resolver] = await F.mainnet.universalResolver.read.resolve(
        [dnsEncodeName(kp.name), res.call],
      );
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
        await F.mainnetV1.setupResolver(kp.name);
        // await F.mainnetV1.ownedResolver.write.multicall([res.write]);
        await F.mainnetV1.walletClient.sendTransaction({
          to: F.mainnetV1.ownedResolver.address,
          data: res.write,
        });
        const [answer, resolver] =
          await F.mainnet.universalResolver.read.resolve([
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
        await F.mainnet.setupName(kp);
        const [res] = makeResolutions(kp);
        await F.mainnet.ownedResolver.write.multicall([[res.write]]);
        const [answer, resolver] =
          await F.mainnet.universalResolver.read.resolve([
            dnsEncodeName(kp.name),
            res.call,
          ]);
        expect(resolver).toEqualAddress(F.mainnet.ownedResolver.address);
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
          await F.mainnet.universalResolver.read.resolve([
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
      await expect(F.mainnet.universalResolver)
        .read("resolve", [dnsEncodeName("test.eth"), dummySelector])
        .toBeRevertedWithCustomError("UnsupportedResolverProfile")
        .withArgs(dummySelector);
    });
    for (const res of makeResolutions(kp)) {
      it(res.desc, async () => {
        const F = await loadFixture(fixture);
        await F.namechain.setupName(kp);
        await F.namechain.ownedResolver.write.multicall([[res.write]]);
        const [answer, resolver] =
          await F.mainnet.universalResolver.read.resolve([
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
      const [answer, resolver] = await F.mainnet.universalResolver.read.resolve(
        [dnsEncodeName(kp.name), bundle.call],
      );
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
