import hre from "hardhat";
import { afterAll, describe, expect, it } from "vitest";
import { namehash, stringToHex, zeroAddress } from "viem";
import { BrowserProvider } from "ethers/providers";
import { serve } from "@namestone/ezccip/serve";
import { Gateway } from "../../lib/unruggable-gateways/src/gateway.js";
import { UncheckedRollup } from "../../lib/unruggable-gateways/src/UncheckedRollup.js";
import { shouldSupportInterfaces } from "@ensdomains/hardhat-chai-matchers-viem/behaviour";

import { shouldSupportFeatures } from "../utils/supportsFeatures.js";
import { deployV1Fixture } from "../fixtures/deployV1Fixture.js";
import { deployV2Fixture } from "../fixtures/deployV2Fixture.js";
import {
  bundleCalls,
  COIN_TYPE_ETH,
  type KnownProfile,
  makeResolutions,
} from "../utils/resolutions.ts";
import { dnsEncodeName, splitName } from "../utils/utils.js";
import { encodeRRs, makeTXT } from "./rr.js";
import { deployArtifact } from "../fixtures/deployArtifact.js";
import { urgArtifact } from "../fixtures/externalArtifacts.js";
import { expectVar } from "../utils/expectVar.ts";

// sufficient to satisfy: `abi.decode(DNSSEC.RRSetWithSignature[])`
const dnsOracleGateway =
  'data:application/json,{"data":"0x0000000000000000000000000000000000000000000000000000000000000000"}';

const network = await hre.network.connect();

async function fixture() {
  const mainnetV1 = await deployV1Fixture(network);
  const mainnetV2 = await deployV2Fixture(network, true); // CCIP on UR
  const namechain = await deployV2Fixture(network);
  const mockDNSSEC = await network.viem.deployContract("MockDNSSEC");
  const dnsTLDResolverV1 = await network.viem.deployContract(
    "OffchainDNSResolver",
    [mainnetV1.ensRegistry.address, mockDNSSEC.address, dnsOracleGateway],
  );
  const oracleGatewayProvider = await network.viem.deployContract(
    "GatewayProvider",
    [mainnetV2.walletClient.account.address, [dnsOracleGateway]],
  );
  const dnsTLDResolver = await network.viem.deployContract("DNSTLDResolver", [
    mainnetV1.ensRegistry.address,
    dnsTLDResolverV1.address,
    mainnetV2.rootRegistry.address,
    mockDNSSEC.address,
    oracleGatewayProvider.address,
    mainnetV2.batchGatewayProvider.address,
  ]);
  await mainnetV2.setupName({
    name: "com",
    resolverAddress: dnsTLDResolver.address,
  });
  const gateway = new Gateway(
    new UncheckedRollup(new BrowserProvider(network.provider)),
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
  const ethResolver = await mainnetV2.deployDedicatedResolver();
  const ethTLDResolver = await network.viem.deployContract("ETHTLDResolver", [
    mainnetV1.ensRegistry.address,
    mainnetV1.batchGatewayProvider.address,
    zeroAddress, // burnAddressV1
    ethResolver.address,
    verifierAddress,
    namechain.datastore.address,
    namechain.ethRegistry.address,
    32,
  ]);
  const dnsRegistryResolver = await network.viem.deployContract(
    "DNSRegistryResolver",
    [ethTLDResolver.address],
  );
  return {
    mainnetV2,
    namechain,
    mockDNSSEC,
    dnsTLDResolver,
    dnsRegistryResolver,
    ethTLDResolver,
    ethResolver,
  };
}

describe("DNSRegistryResolver", () => {
  shouldSupportInterfaces({
    contract: () =>
      network.networkHelpers
        .loadFixture(fixture)
        .then((F) => F.dnsRegistryResolver),
    interfaces: ["IERC165", "IExtendedDNSResolver", "IFeatureSupporter"],
  });

  shouldSupportFeatures({
    contract: () =>
      network.networkHelpers
        .loadFixture(fixture)
        .then((F) => F.dnsRegistryResolver),
    features: {
      RESOLVER: ["RESOLVE_MULTICALL"],
    },
  });

  function testRegistry(name: string, suffixName: string) {
    const prefixName = suffixName
      ? name.slice(0, -(suffixName.length + 1))
      : name;

    it(`${prefixName}[${suffixName}]`, async () => {
      const F = await network.networkHelpers.loadFixture(fixture);
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
      if (!name.endsWith(suffixName)) throw new Error("expected suffix");
      const { dedicatedResolver } = await F.namechain.setupName({
        name: prefixName,
      });
      const parentRegistry = F.namechain.rootRegistry;
      await F.mockDNSSEC.write.setResponse([
        encodeRRs([
          makeTXT(
            kp.name,
            `ENS1 ${F.dnsRegistryResolver.address} ${parentRegistry.address} ${suffixName}`,
          ),
        ]),
      ]);
      const bundle = bundleCalls(makeResolutions(kp));
      await dedicatedResolver.write.multicall([
        bundle.resolutions.map((x) => x.writeDedicated),
      ]);
      const [answer, resolver] =
        await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(kp.name),
          bundle.call,
        ]);
      expectVar({ resolver }).toEqualAddress(F.dnsTLDResolver.address);
      bundle.expect(answer);
      const directAnswer = await F.ethTLDResolver.read.resolveWithRegistry([
        parentRegistry.address,
        namehash(suffixName),
        dnsEncodeName(name),
        bundle.call,
      ]);
      bundle.expect(directAnswer);
    });
  }

  testRegistry("test.com", "com");
  testRegistry("test.com", "");
  testRegistry("sub.test.com", "com");
  testRegistry("a.b.c.test.com", "test.com");

  it(`invalid suffix`, async () => {
    const F = await network.networkHelpers.loadFixture(fixture);
    await expect(
      F.ethTLDResolver.read.resolveWithRegistry([
        F.namechain.rootRegistry.address,
        namehash("org"),
        dnsEncodeName("test.com"),
        "0x00000000",
      ]),
    ).toBeRevertedWithCustomError("UnreachableName");
  });

  describe("invalid context", () => {
    for (const context of [
      "0x", // too short
      "com", // not 0x
      zeroAddress, // missing trailing space
      "0x000000000000000000000000000000000000000g ", // not hex
    ]) {
      it(context, async () => {
        const F = await network.networkHelpers.loadFixture(fixture);
        await expect(
          F.dnsRegistryResolver.read.resolve([
            dnsEncodeName("test.com"),
            "0x00000000",
            stringToHex(context),
          ]),
        ).toBeRevertedWithCustomError("InvalidContext");
      });
    }
  });
});
