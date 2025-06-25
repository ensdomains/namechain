import hre from "hardhat";
import { shouldSupportInterfaces } from "@ensdomains/hardhat-chai-matchers-viem/behaviour";
import { describe, expect, it } from "vitest";
import { deployV1Fixture } from "../fixtures/deployV1Fixture.js";
import { deployV2Fixture } from "../fixtures/deployV2Fixture.js";
import { dummyShapeshiftResolverArtifact } from "../fixtures/ens-contracts/DummyShapeshiftResolver.js";
import {
  bundleCalls,
  type KnownProfile,
  makeResolutions,
} from "../utils/resolutions.js";
import { dnsEncodeName, expectVar } from "../utils/utils.js";
import { encodeRRs, TXT } from "./gasless.js";

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
    [
      // "data"" is sufficient to satisfy: `abi.decode(DNSSEC.RRSetWithSignature[])`
      'data:application/json,{"data":"0x0000000000000000000000000000000000000000000000000000000000000000"}',
    ],
  ]);
  await mainnetV2.setupName({
    name: "com",
    resolverAddress: dnsTLDResolver.address,
  });
  return {
    mainnetV1,
    mainnetV2,
    ssResolver,
    mockDNSSEC,
    dnsTLDResolver,
  };
}

const basicProfile: KnownProfile = {
  name: "eth.com",
  addresses: [{ coinType: 1n, value: "0x1234" }],
};
const multiProfile: KnownProfile = {
  ...basicProfile,
  texts: [{ key: "url", value: "https://ens.domains" }],
  contenthash: { value: "0xabcd" },
};

describe("DNSTLDResolver", () => {
  shouldSupportInterfaces({
    contract: () =>
      chain.networkHelpers.loadFixture(fixture).then((F) => F.dnsTLDResolver),
    interfaces: ["IERC165", "IExtendedResolver"],
  });

  function testProfiles(
    name: string,
    factory: (kp: KnownProfile) => () => Promise<void>,
  ) {
    it(name, factory(basicProfile));
    it(`${name} multicall`, factory(multiProfile));
  }

  describe("still registered on V1", () => {
    testProfiles("immediate", (kp) => async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mainnetV1.setupName(kp);
      const bundle = bundleCalls(makeResolutions(kp));
      for (const res of bundle.resolutions) {
        await F.mainnetV1.walletClient.sendTransaction({
          to: F.mainnetV1.ownedResolver.address,
          data: res.write, // V1 OwnedResolver lacks multicall()
        });
      }
      const [answer, resolver] =
        await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(multiProfile.name),
          bundle.call,
        ]);
      expectVar({ resolver }).toEqualAddress(F.dnsTLDResolver.address);
      bundle.expect(answer);
    });

    testProfiles("onchain extended", (kp) => async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mainnetV1.setupName({
        name: kp.name,
        resolverAddress: F.ssResolver.address,
      });
      const bundle = bundleCalls(makeResolutions(kp));
      await F.ssResolver.write.setExtended([true]);
      for (const res of bundle.resolutions) {
        await F.ssResolver.write.setResponse([res.call, res.answer]);
      }
      const [answer, resolver] =
        await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(kp.name),
          bundle.call,
        ]);
      expectVar({ resolver }).toEqualAddress(F.dnsTLDResolver.address);
      bundle.expect(answer);
    });

    testProfiles("offchain extended", (kp) => async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mainnetV1.setupName({
        ...kp,
        resolverAddress: F.ssResolver.address,
      });
      const bundle = bundleCalls(makeResolutions(kp));
      await F.ssResolver.write.setExtended([true]);
      await F.ssResolver.write.setOffchain([true]);
      for (const res of bundle.resolutions) {
        await F.ssResolver.write.setResponse([res.call, res.answer]);
      }
      const [answer, resolver] =
        await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(kp.name),
          bundle.call,
        ]);
      expectVar({ resolver }).toEqualAddress(F.dnsTLDResolver.address);
      bundle.expect(answer);
    });
  });

  it("imported on V2", async () => {
    const F = await chain.networkHelpers.loadFixture(fixture);
    const bundle = bundleCalls(makeResolutions(multiProfile));
    await F.mainnetV2.setupName({ name: multiProfile.name });
    await F.mainnetV2.dedicatedResolver.write.multicall([
      bundle.resolutions.map((x) => x.writeDedicated),
    ]);
    const [answer, resolver] = await F.mainnetV2.universalResolver.read.resolve(
      [dnsEncodeName(multiProfile.name), bundle.call],
    );
    expectVar({ resolver }).toEqualAddress(
      F.mainnetV2.dedicatedResolver.address,
    );
    bundle.expect(answer);
  });

  describe("DNSSEC", () => {
    it("no ENS1", async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      const bundle = bundleCalls(makeResolutions(basicProfile));
      await expect(
        F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(multiProfile.name),
          bundle.call,
        ]),
      ).rejects.toThrow(); // TODO: FIX ME
      // .toBeRevertedWithCustomError<typeof F.dnsTLDResolver.abi>(
      //   "UnreachableName",
      // )
      // .withArgs(dnsEncodeName(basicProfile.name));
    });

    testProfiles("ENS1 w/address onchain immediate", (kp) => async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mockDNSSEC.write.setResponse([
        encodeRRs([
          TXT(kp.name, `ENS1 ${F.mainnetV2.dedicatedResolver.address}`),
        ]),
      ]);
      const bundle = bundleCalls(makeResolutions(kp));
      await F.mainnetV2.dedicatedResolver.write.multicall([
        bundle.resolutions.map((x) => x.writeDedicated),
      ]);
      const [answer, resolver] =
        await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(multiProfile.name),
          bundle.call,
        ]);
      expectVar({ resolver }).toEqualAddress(F.dnsTLDResolver.address);
      bundle.expect(answer);
    });

    testProfiles("ENS1 w/name onchain immediate", (kp) => async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      const name = "resolver.eth";
      await F.mainnetV2.setupName({
        name,
        resolverAddress: F.ssResolver.address,
      });
      const bundle = bundleCalls(makeResolutions(kp));
      for (const res of bundle.resolutions) {
        await F.ssResolver.write.setResponse([res.call, res.answer]);
      }
      await F.mockDNSSEC.write.setResponse([
        encodeRRs([TXT(kp.name, `ENS1 ${name}`)]),
      ]);
      const [answer, resolver] =
        await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(multiProfile.name),
          bundle.call,
        ]);
      expectVar({ resolver }).toEqualAddress(F.dnsTLDResolver.address);
      bundle.expect(answer);
    });

    testProfiles("ENS1 w/name offchain extended", (kp) => async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      const name = "resolver.eth";
      await F.mainnetV2.setupName({
        name,
        resolverAddress: F.ssResolver.address,
      });
      const bundle = bundleCalls(makeResolutions(kp));
      await F.ssResolver.write.setExtended([true]);
      await F.ssResolver.write.setOffchain([true]);
      for (const res of bundle.resolutions) {
        await F.ssResolver.write.setResponse([res.call, res.answer]);
      }
      await F.mockDNSSEC.write.setResponse([
        encodeRRs([TXT(kp.name, `ENS1 ${name}`)]),
      ]);
      const [answer, resolver] =
        await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(multiProfile.name),
          bundle.call,
        ]);
      expectVar({ resolver }).toEqualAddress(F.dnsTLDResolver.address);
      bundle.expect(answer);
    });
  });
});
