import { shouldSupportInterfaces } from "@ensdomains/hardhat-chai-matchers-viem/behaviour";
import hre from "hardhat";
import { describe, it } from "vitest";

import {
  type KnownProfile,
  bundleCalls,
  makeResolutions,
} from "../../utils/resolutions.js";
import { shouldSupportFeatures } from "../../utils/supportsFeatures.js";
import { dnsEncodeName } from "../../utils/utils.js";
import { deployV1Fixture } from "../fixtures/deployV1Fixture.js";
import { deployV2Fixture } from "../fixtures/deployV2Fixture.js";

const network = await hre.network.connect();

async function fixture() {
  const mainnetV1 = await deployV1Fixture(network, true);
  const mainnetV2 = await deployV2Fixture(network, true);
  const ensV1Resolver = await network.viem.deployContract("ENSV1Resolver", [
    mainnetV1.ensRegistry.address,
    mainnetV1.batchGatewayProvider.address,
  ]);
  return { mainnetV1, mainnetV2, ensV1Resolver };
}

describe("ENSV1Resolver", () => {
  /// https://github.com/ensdomains/ens-contracts/blob/staging/test/universalResolver/TestResolverCaller.test.ts
  /// https://github.com/ensdomains/ens-contracts/blob/staging/test/universalResolver/TestUniversalResolver.test.ts

  shouldSupportInterfaces({
    contract: () =>
      network.networkHelpers.loadFixture(fixture).then((F) => F.ensV1Resolver),
    interfaces: ["IERC165", "IERC7996", "IExtendedResolver"],
  });

  shouldSupportFeatures({
    contract: () =>
      network.networkHelpers.loadFixture(fixture).then((F) => F.ensV1Resolver),
    features: {
      RESOLVER: ["RESOLVE_MULTICALL"],
    },
  });

  it("2LD", async () => {
    const F = await network.networkHelpers.loadFixture(fixture);
    const kp: KnownProfile = {
      name: "test.eth",
    };
    const res = bundleCalls(makeResolutions(kp));
    await F.mainnetV1.setupName(kp);
    await F.mainnetV1.publicResolver.write.multicall([
      res.resolutions.map((x) => x.write),
    ]);
    res.expect(
      await F.ensV1Resolver.read.resolve([dnsEncodeName(kp.name), res.call]),
    );
  });

  it("3LD", async () => {
    const F = await network.networkHelpers.loadFixture(fixture);
    const kp: KnownProfile = {
      name: "sub.test.eth",
    };
    const res = bundleCalls(makeResolutions(kp));
    await F.mainnetV1.setupName(kp);
    await F.mainnetV1.publicResolver.write.multicall([
      res.resolutions.map((x) => x.write),
    ]);
    res.expect(
      await F.ensV1Resolver.read.resolve([dnsEncodeName(kp.name), res.call]),
    );
  });
});
