import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox-viem/network-helpers.js";
import { shouldSupportInterfaces } from "@ensdomains/hardhat-chai-matchers-viem/behaviour";
import {
  type Address,
  encodeErrorResult,
  parseAbi,
  parseEventLogs,
  zeroAddress,
} from "viem";
import { expect } from "chai";
import {
  ALL_ROLES,
  MAX_EXPIRY,
  deployV2Fixture,
} from "./fixtures/deployV2Fixture.js";
import { deployV1Fixture } from "./fixtures/deployV1Fixture.js";
import { launchBatchGateway } from "./utils/localBatchGateway.js";
import { deployArtifact } from "./artifacts/deploy.js";
import { urgArtifact } from "./artifacts/artifacts.js";
import { UncheckedRollup } from "../lib/unruggable-gateways/src/UncheckedRollup.js";
import { Gateway } from "../lib/unruggable-gateways/src/gateway.js";
import { dnsEncodeName, labelhashUint256, splitName } from "./utils/utils.js";
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
      client: { public: mainnet.publicClient }, // CCIP on FR
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
    ensureRegistry,
  };
  async function ensureRegistry(
    {
      name,
      owner = namechain.accounts[0].address,
      expiry = MAX_EXPIRY,
      roles = ALL_ROLES,
    }: {
      name: string;
      owner?: Address;
      expiry?: bigint;
      roles?: bigint;
    },
    network = namechain,
  ) {
    const labels = splitName(name);
    if (labels.pop() !== "eth") throw new Error("expected eth");
    if (!labels.length) throw new Error("expected 2LD+");
    let parentRegistry = network.ethRegistry;
    for (let i = labels.length - 1; i > 0; i--) {
      const registry = await hre.viem.deployContract("PermissionedRegistry", [
        network.datastore.address,
        zeroAddress,
        ALL_ROLES,
      ]);
      await parentRegistry.write.register([
        labels[i],
        owner,
        registry.address,
        zeroAddress,
        roles,
        expiry,
      ]);
      parentRegistry = registry;
    }
    const hash = await parentRegistry.write.register([
      labels[0],
      owner,
      zeroAddress,
      network.ownedResolver.address,
      roles,
      expiry,
    ]);
    const receipt = await network.publicClient.getTransactionReceipt({
      hash,
    });
    const [log] = parseEventLogs({
      abi: parentRegistry.abi,
      eventName: "NewSubname",
      logs: receipt.logs,
    });
    return { parentRegistry, ...log.args };
  }
}

const dummySelector = "0x12345678";
const testAddress = "0x8000000000000000000000000000000000000001";

describe("ETHFallbackResolver", () => {
  shouldSupportInterfaces({
    contract: () => loadFixture(fixture).then((F) => F.ethFallbackResolver),
    interfaces: ["IERC165", "IExtendedResolver"],
  });

  describe("unregistered", () => {
    for (const name of ["test.eth", "sub.test.eth"]) {
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
  });

  describe("registered on mainnet", () => {
    for (const name of ["test.eth", "sub.test.eth"]) {
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
        await F.ensureRegistry(kp, F.mainnet);
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
    for (const name of ["test.eth", "sub.test.eth"]) {
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
        await F.ensureRegistry(kp);
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
    for (const name of ["test.eth", "sub.test.eth"]) {
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
        const { parentRegistry, labelHash } = await F.ensureRegistry(kp);
        const [res] = makeResolutions(kp);
        await F.namechain.ownedResolver.write.multicall([[res.write]]);
        const answer = await F.ethFallbackResolver.read.resolve([
          dnsEncodeName(kp.name),
          res.call,
        ]);
        res.expect(answer);
        await parentRegistry.write.relinquish([labelHash]);
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
      primary: {
        value: "test.eth",
      },
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
        await F.ensureRegistry(kp);
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
      await F.ensureRegistry(kp);
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
      await F.ensureRegistry(kp);
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
