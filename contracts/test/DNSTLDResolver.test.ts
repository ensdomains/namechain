import hre from "hardhat";
import { shouldSupportInterfaces } from "@ensdomains/hardhat-chai-matchers-viem/behaviour";
import { expect } from "chai";
import { afterEach, afterAll, describe, it, assert } from "vitest";
import { deployV1Fixture } from "./fixtures/deployV1Fixture.js";
import { deployV2Fixture } from "./fixtures/deployV2Fixture.js";
import { dummyShapeshiftResolverArtifact } from "./fixtures/ens-contracts/DummyShapeshiftResolver.js";
import {
  bundleCalls,
  KnownProfile,
  makeResolutions,
} from "./utils/resolutions.js";
import { dnsEncodeName, expectVar } from "./utils/utils.js";

const chain = await hre.network.connect();

async function fixture() {
  const mainnetV1 = await deployV1Fixture(chain, true); // CCIP on UR
  const mainnetV2 = await deployV2Fixture(chain, true); // CCIP on UR
  const ssResolver = await chain.viem.deployContract(
    dummyShapeshiftResolverArtifact,
  );
  const mockDNSSEC = await chain.viem.deployContract("MockDNSSEC");
  const dnsTLDResolver = await chain.viem.deployContract("DNSTLDResolver", [
    mainnetV1.universalResolver.address,
    mainnetV2.universalResolver.address,
    mockDNSSEC.address,
    [],
  ]);
  await mainnetV2.setupName({
    name: "com",
    resolverAddress: dnsTLDResolver.address,
  });
  return {
    mainnetV1,
    mainnetV2,
    ssResolver,
    dnsTLDResolver,
  };
}

const profile: KnownProfile = {
  name: "eth.com",
  addresses: [{ coinType: 1n, value: "0x1234" }],
  texts: [{ key: "url", value: "https://ens.domains" }],
};

describe("DNSTLDResolver", () => {
  shouldSupportInterfaces({
    contract: () =>
      chain.networkHelpers.loadFixture(fixture).then((F) => F.dnsTLDResolver),
    interfaces: ["IERC165", "IExtendedResolver"],
  });

  describe("still registered on V1", () => {
    it("immediate", async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mainnetV1.setupName(profile);
      const bundle = bundleCalls(makeResolutions(profile));
      for (const res of bundle.resolutions) {
        await F.mainnetV1.walletClient.sendTransaction({
          to: F.mainnetV1.ownedResolver.address,
          data: res.write, // V1 OwnedResolver lacks multicall()
        });
      }
      const [answer, resolver] =
        await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(profile.name),
          bundle.call,
        ]);
      expectVar({ resolver }).toEqualAddress(F.dnsTLDResolver.address);
      bundle.expect(answer);
    });

    it("onchain extended", async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mainnetV1.setupName({
        name: profile.name,
        resolverAddress: F.ssResolver.address,
      });
      const bundle = bundleCalls(makeResolutions(profile));
      await F.ssResolver.write.setExtended([true]);
      for (const res of bundle.resolutions) {
        await F.ssResolver.write.setResponse([res.call, res.answer]);
      }
      const [answer, resolver] =
        await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(profile.name),
          bundle.call,
        ]);
      expectVar({ resolver }).toEqualAddress(F.dnsTLDResolver.address);
      bundle.expect(answer);
    });

    // it("offchain extended", async () => {
    //   const F = await chain.networkHelpers.loadFixture(fixture);
    //   await F.mainnetV1.setupName({
    //     ...profile,
    //     resolverAddress: F.ssResolver.address,
    //   });
    //   const bundle = bundleCalls(makeResolutions(profile));
    //   await F.ssResolver.write.setExtended([true]);
    //   await F.ssResolver.write.setOffchain([true]);
    //   for (const res of bundle.resolutions) {
    //     await F.ssResolver.write.setResponse([res.call, res.answer]);
    //   }
    //   const [answer, resolver] =
    //     await F.mainnetV2.universalResolver.read.resolve([
    //       dnsEncodeName(profile.name),
    //       bundle.call,
    //     ]);
    //   expectVar({ resolver }).toEqualAddress(F.dnsTLDResolver.address);
    //   bundle.expect(answer);
    // });
  });

  it("imported on V2", async () => {
    const F = await chain.networkHelpers.loadFixture(fixture);
    const bundle = bundleCalls(makeResolutions(profile));
    await F.mainnetV2.setupName({ name: profile.name });
    await F.mainnetV2.dedicatedResolver.write.multicall([
      bundle.resolutions.map((x) => x.writeDedicated),
    ]);
    const [answer, resolver] = await F.mainnetV2.universalResolver.read.resolve(
      [dnsEncodeName(profile.name), bundle.call],
    );
    expectVar({ resolver }).toEqualAddress(
      F.mainnetV2.dedicatedResolver.address,
    );
    bundle.expect(answer);
  });
});
