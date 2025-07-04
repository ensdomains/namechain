import hre from "hardhat";
import { shouldSupportInterfaces } from "@ensdomains/hardhat-chai-matchers-viem/behaviour";
import { afterAll, describe, it } from "vitest";
import { deployV1Fixture } from "../fixtures/deployV1Fixture.js";
import { deployV2Fixture } from "../fixtures/deployV2Fixture.js";
import {
  bundleCalls,
  COIN_TYPE_ETH,
  type KnownProfile,
  makeResolutions,
} from "../utils/resolutions.js";
import { BrowserProvider } from "ethers/providers";
import { dnsEncodeName, expectVar, splitName } from "../utils/utils.js";
import { encodeRRs, makeTXT } from "./rr.js";
import { zeroAddress } from "viem";
import { Gateway } from "../../lib/unruggable-gateways/src/gateway.js";
import { deployArtifact } from "../fixtures/deployArtifact.js";
import { UncheckedRollup } from "../../lib/unruggable-gateways/src/UncheckedRollup.js";
import { serve } from "@namestone/ezccip/serve";
import { urgArtifact } from "../fixtures/externalArtifacts.js";
import { shouldSupportsFeatures } from "../utils/supportsFeatures.js";

const chain = await hre.network.connect();

async function fixture() {
  const mainnetV1 = await deployV1Fixture(chain);
  const mainnetV2 = await deployV2Fixture(chain, true); // CCIP on UR
  const namechain = await deployV2Fixture(chain);
  const mockDNSSEC = await chain.viem.deployContract("MockDNSSEC");
  const dnsTLDResolver = await chain.viem.deployContract("DNSTLDResolver", [
    mainnetV1.universalResolver.address,
    mainnetV2.universalResolver.address,
    mockDNSSEC.address,
    [
      // "data" is sufficient to satisfy: `abi.decode(DNSSEC.RRSetWithSignature[])`
      'data:application/json,{"data":"0x0000000000000000000000000000000000000000000000000000000000000000"}',
    ],
  ]);
  await mainnetV2.setupName({
    name: "com",
    resolverAddress: dnsTLDResolver.address,
  });
  const gateway = new Gateway(
    new UncheckedRollup(new BrowserProvider(chain.provider)),
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
  const ethFallbackResolver = await chain.viem.deployContract(
    "ETHFallbackResolver",
    [
      zeroAddress, // ethRegistarV1
      zeroAddress, // universalResolverV1
      zeroAddress, // burnAddressV1
      ethResolver.address,
      verifierAddress,
      namechain.datastore.address,
      namechain.ethRegistry.address,
    ],
  );
  const dnsRemoteRegistryResolver = await chain.viem.deployContract(
    "DNSRemoteRegistryResolver",
    [ethFallbackResolver.address],
  );
  return {
    mainnetV2,
    namechain,
    mockDNSSEC,
    dnsTLDResolver,
    dnsRemoteRegistryResolver,
    ethFallbackResolver,
    ethResolver,
  };
}

describe("DNSRemoteRegistryResolver", () => {
  shouldSupportInterfaces({
    contract: () =>
      chain.networkHelpers
        .loadFixture(fixture)
        .then((F) => F.dnsRemoteRegistryResolver),
    interfaces: ["IERC165", "IExtendedDNSResolver", "IFeatureSupporter"],
  });

  shouldSupportsFeatures({
    contract: () =>
      chain.networkHelpers
        .loadFixture(fixture)
        .then((F) => F.dnsRemoteRegistryResolver),
    features: {
      RESOLVER: ["RESOLVE_MULTICALL"],
    },
  });

  function testRegistry(name: string, suffixName: string, remoteName: string) {
    it(`${name}/${suffixName} => ${remoteName}`, async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      const kp: KnownProfile = {
        name,
        addresses: [
          {
            coinType: COIN_TYPE_ETH,
            value: "0x8000000000000000000000000000000000000001",
          },
        ],
        texts: [{ key: "url", value: "https://ens.domains" }],
      };
      const { registries } = await F.namechain.setupName({
        name: remoteName,
      });
      const depth = splitName(name).length - splitName(suffixName).length;
      const registry = registries[registries.length - depth];
      await F.mockDNSSEC.write.setResponse([
        encodeRRs([
          makeTXT(
            kp.name,
            `ENS1 ${F.dnsRemoteRegistryResolver.address} ${registry.address} ${suffixName}`,
          ),
        ]),
      ]);
      const bundle = bundleCalls(makeResolutions(kp));
      await F.namechain.walletClient.sendTransaction({
        to: F.namechain.dedicatedResolver.address,
        data: bundle.writeDedicated,
      });
      const [answer, resolver] =
        await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(kp.name),
          bundle.call,
        ]);
      expectVar({ resolver }).toEqualAddress(F.dnsTLDResolver.address);
      bundle.expect(answer);
    });
  }

  testRegistry("test.com", "com", "test");
  testRegistry("sub.test.com", "com", "sub.test.a.b.c");
  testRegistry("sub.test.com", "test.com", "sub.a.b.c");
});
