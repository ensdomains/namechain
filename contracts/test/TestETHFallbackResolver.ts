import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox-viem/network-helpers.js";
import { expect } from "chai";
import { shouldSupportInterfaces } from "@ensdomains/hardhat-chai-matchers-viem/behaviour";
import {
  ALL_ROLES,
  MAX_EXPIRY,
  deployEnsFixture,
} from "./fixtures/deployEnsFixture.js";
import { deployArtifact, urgArtifact } from "./fixtures/deployArtifact.js";
import {
  type Hex,
  encodeErrorResult,
  encodeFunctionData,
  namehash,
  parseAbi,
  zeroAddress,
} from "viem";
import { UncheckedRollup } from "../lib/unruggable-gateways/src/UncheckedRollup.js";
import { Gateway } from "../lib/unruggable-gateways/src/gateway.js";
import { dnsEncodeName, labelhashUint256, splitName } from "./utils/utils.js";
import { serve } from "@namestone/ezccip/serve";
import { BrowserProvider } from "ethers/providers";
import {
  type KnownProfile,
  bundleCalls,
  makeResolutions,
} from "../lib/ens-contracts/test/universalResolver/utils.js";

async function fixture() {
  const mainnet = await deployEnsFixture(true);
  const namechain = await deployEnsFixture();
  const gateway = new Gateway(
    new UncheckedRollup(new BrowserProvider(hre.network.provider))
  );
  gateway.latestCache.cacheMs = 0;
  gateway.commitCacheMap.cacheMs = 0;
  gateway.callLRU.max = 0;
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
  const ethFallbackRegistry = await hre.viem.deployContract(
    "ETHFallbackResolver",
    [
      mainnet.rootRegistry.address,
      namechain.datastore.address,
      namechain.ethRegistry.address,
      verifierAddress,
    ]
  );
  await mainnet.rootRegistry.write.setResolver([
    labelhashUint256("eth"),
    ethFallbackRegistry.address,
  ]);
  const publicResolver = await hre.viem.deployContract("PublicResolver");
  return {
    ethFallbackRegistry,
    publicResolver,
    mainnet,
    namechain,
    ensureRegistry,
    writeResolutions,
  };
  async function writeResolutions(p: KnownProfile) {
    // TODO: move this to ens-contracts/
    // TODO: add contenthash()
    const node = namehash(p.name);
    const calls: Hex[] = [];
    if (p.addresses) {
      for (const x of p.addresses) {
        calls.push(
          encodeFunctionData({
            abi: publicResolver.abi,
            functionName: "setAddr",
            args: [node, x.coinType, x.encodedAddress],
          })
        );
      }
    }
    if (p.texts) {
      for (const x of p.texts) {
        calls.push(
          encodeFunctionData({
            abi: publicResolver.abi,
            functionName: "setText",
            args: [node, x.key, x.value],
          })
        );
      }
    }
    if (p.primary) {
      calls.push(
        encodeFunctionData({
          abi: publicResolver.abi,
          functionName: "setName",
          args: [node, p.primary.name],
        })
      );
    }
    if (calls.length) {
      await publicResolver.write.multicall([calls]);
    }
  }
  async function ensureRegistry(
    name: string,
    owner = namechain.accounts[0].address
  ) {
    const labels = splitName(name);
    if (labels.pop() !== "eth") throw new Error("expected eth");
    if (!labels.length) throw new Error("expected 2LD+");
    let parentRegistry = namechain.ethRegistry;
    for (let i = labels.length - 1; i > 0; i--) {
      const registry = await hre.viem.deployContract(
        "PermissionedRegistry",
        [namechain.datastore.address, zeroAddress, ALL_ROLES]
      );
      await parentRegistry.write.register([
        labels[i],
        owner,
        registry.address,
        zeroAddress,
        ALL_ROLES,
        MAX_EXPIRY,
      ]);
      parentRegistry = registry;
    }
    await parentRegistry.write.register([
      labels[0],
      owner,
      zeroAddress,
      publicResolver.address,
      ALL_ROLES,
      MAX_EXPIRY,
    ]);
  }
}

const testAddress = "0x8000000000000000000000000000000000000001";

describe("ETHFallbackResolver", () => {
  shouldSupportInterfaces({
    contract: () => loadFixture(fixture).then((F) => F.ethFallbackRegistry),
    interfaces: ["IERC165", "IExtendedResolver"],
  });

  describe("not ejected: resolver unset", () => {
    for (const name of ["eth", "test.eth", "sub.test.eth"]) {
      it(name, async () => {
        const F = await loadFixture(fixture);
        const [res] = makeResolutions({
          name,
          addresses: [{ coinType: 60n, encodedAddress: testAddress }],
        });
        await expect(F.mainnet.universalResolver)
          .read("resolve", [dnsEncodeName(name), res.call])
          .toBeRevertedWithCustomError("ResolverError")
          .withArgs(
            encodeErrorResult({
              abi: parseAbi(["error UnreachableName(bytes)"]),
              args: [dnsEncodeName(name)],
            })
          );
      });
    }
  });

  describe("not ejected: resolver set", () => {
    for (const name of ["test.eth", "sub.test.eth"]) {
      it(name, async () => {
        const F = await loadFixture(fixture);
        const kp: KnownProfile = {
          name,
          addresses: [
            {
              coinType: 60n,
              encodedAddress: testAddress,
            },
          ],
        };
        await F.ensureRegistry(kp.name);
        await F.writeResolutions(kp);
        const [res] = makeResolutions(kp);
        const [answer, resolver] =
          await F.mainnet.universalResolver.read.resolve([
            dnsEncodeName(name),
            res.call,
          ]);
        expect(resolver).toEqualAddress(F.ethFallbackRegistry.address);
        res.expect(answer);
      });
    }
  });

  it("record profiles", async () => {
    const F = await loadFixture(fixture);
    const kp: KnownProfile = {
      name: "test.eth",
      addresses: [
        {
          coinType: 60n,
          encodedAddress: testAddress,
        },
        {
          coinType: 1n,
          encodedAddress: "0x1234",
        },
      ],
      texts: [{ key: "chonk", value: "Chonk" }],
      primary: {
        name: "test.eth",
      },
    };
    await F.ensureRegistry(kp.name);
    await F.writeResolutions(kp);
    const bundle = bundleCalls(makeResolutions(kp));
    const [answer, resolver] =
      await F.mainnet.universalResolver.read.resolve([
        dnsEncodeName(kp.name),
        bundle.call,
      ]);
    expect(resolver).toEqualAddress(F.ethFallbackRegistry.address);
    bundle.expect(answer);
  });
});
