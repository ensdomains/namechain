import hre from "hardhat";
import { shouldSupportInterfaces } from "@ensdomains/hardhat-chai-matchers-viem/behaviour";
import { describe, expect, it } from "vitest";
import { deployV1Fixture } from "../fixtures/deployV1Fixture.js";
import { deployV2Fixture } from "../fixtures/deployV2Fixture.js";
import { dummyShapeshiftResolverArtifact } from "../fixtures/ens-contracts/DummyShapeshiftResolver.js";
import {
  bundleCalls,
  COIN_TYPE_DEFAULT,
  COIN_TYPE_ETH,
  type KnownProfile,
  makeResolutions,
} from "../utils/resolutions.js";
import { dnsEncodeName, expectVar } from "../utils/utils.js";
import { encodeRRs, makeTXT } from "./rr.js";
import { FEATURES } from "../utils/features.js";
import { concat, stringToHex } from "viem";

const chain = await hre.network.connect();

const dnsnameResolver = "dnsname.ens.eth";
const dummyBytes4 = "0x12345678";
const testAddress = "0x8000000000000000000000000000000000000001";
const basicProfile: KnownProfile = {
  name: "test.com",
  addresses: [{ coinType: COIN_TYPE_ETH, value: testAddress }],
};

async function fixture() {
  const mainnetV1 = await deployV1Fixture(chain);
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
      // "data" is sufficient to satisfy: `abi.decode(DNSSEC.RRSetWithSignature[])`
      'data:application/json,{"data":"0x0000000000000000000000000000000000000000000000000000000000000000"}',
    ],
  ]);
  await mainnetV2.setupName({
    name: "com",
    resolverAddress: dnsTLDResolver.address,
  });
  const dnsTXTResolver = await chain.viem.deployContract("DNSTXTResolver");
  await mainnetV2.setupName({
    name: dnsnameResolver,
    resolverAddress: dnsTXTResolver.address,
  });
  return {
    mainnetV1,
    mainnetV2,
    ssResolver,
    mockDNSSEC,
    dnsTLDResolver,
    dnsTXTResolver,
  };
}

describe("DNSTLDResolver", () => {
  shouldSupportInterfaces({
    contract: () =>
      chain.networkHelpers.loadFixture(fixture).then((F) => F.dnsTLDResolver),
    interfaces: ["IERC165", "IExtendedResolver", "IFeatureSupporter"],
  });

  it("supportsFeature: resolve(multicall)", async () => {
    const F = await chain.networkHelpers.loadFixture(fixture);
    await expect(
      F.dnsTLDResolver.read.supportsFeature([
        FEATURES.RESOLVER.RESOLVE_MULTICALL,
      ]),
    ).resolves.toStrictEqual(true);
  });

  function testProfiles(
    name: string,
    factory: (kp: KnownProfile) => () => Promise<void>,
  ) {
    it(name, factory(basicProfile));
    it(
      `${name} multicall`,
      factory({
        ...basicProfile,
        texts: [{ key: "url", value: "https://ens.domains" }],
        contenthash: { value: "0xabcd" },
      }),
    );
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
          dnsEncodeName(kp.name),
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
    const bundle = bundleCalls(makeResolutions(basicProfile));
    await F.mainnetV2.setupName(basicProfile);
    await F.mainnetV2.dedicatedResolver.write.multicall([
      bundle.resolutions.map((x) => x.writeDedicated),
    ]);
    const [answer, resolver] = await F.mainnetV2.universalResolver.read.resolve(
      [dnsEncodeName(basicProfile.name), bundle.call],
    );
    expectVar({ resolver }).toEqualAddress(
      F.mainnetV2.dedicatedResolver.address,
    );
    bundle.expect(answer);
  });

  describe("DNSSEC", () => {
    it("no ENS1", async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await expect(
        F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(basicProfile.name),
          dummyBytes4,
        ]),
      )
        .toBeRevertedWithCustomErrorFrom(F.dnsTLDResolver, "UnreachableName") // TODO: fix after merge
        .withArgs([dnsEncodeName(basicProfile.name)]);
    });

    describe("via address", () => {
      testProfiles("address -> onchain immediate", (kp) => async () => {
        const F = await chain.networkHelpers.loadFixture(fixture);
        await F.mockDNSSEC.write.setResponse([
          encodeRRs([
            makeTXT(kp.name, `ENS1 ${F.mainnetV2.dedicatedResolver.address}`),
          ]),
        ]);
        const bundle = bundleCalls(makeResolutions(kp));
        await F.mainnetV2.dedicatedResolver.write.multicall([
          bundle.resolutions.map((x) => x.writeDedicated),
        ]);
        const [answer, resolver] =
          await F.mainnetV2.universalResolver.read.resolve([
            dnsEncodeName(kp.name),
            bundle.call,
          ]);
        expectVar({ resolver }).toEqualAddress(F.dnsTLDResolver.address);
        bundle.expect(answer);
      });
    });

    describe("via name", () => {
      testProfiles("onchain immediate", (kp) => async () => {
        const F = await chain.networkHelpers.loadFixture(fixture);
        const name = "myresolver.eth";
        await F.mainnetV2.setupName({
          name,
          resolverAddress: F.ssResolver.address,
        });
        const bundle = bundleCalls(makeResolutions(kp));
        for (const res of bundle.resolutions) {
          await F.ssResolver.write.setResponse([res.call, res.answer]);
        }
        await F.mockDNSSEC.write.setResponse([
          encodeRRs([makeTXT(kp.name, `ENS1 ${name}`)]),
        ]);
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
        const name = "myresolver.eth";
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
          encodeRRs([makeTXT(kp.name, `ENS1 ${name}`)]),
        ]);
        const [answer, resolver] =
          await F.mainnetV2.universalResolver.read.resolve([
            dnsEncodeName(kp.name),
            bundle.call,
          ]);
        expectVar({ resolver }).toEqualAddress(F.dnsTLDResolver.address);
        bundle.expect(answer);
      });
    });
  });

  describe("DNSTXTResolver", () => {
    const url = "https://ens.domains";
    const contenthash = "0xabcdef";
    const anotherAddress = "0x1234567812345678123456781234567812345678";
    const x = `0x${"a".repeat(64)}` as const;
    const y = `0x${"b".repeat(64)}` as const;
    const context = `a[60]=${testAddress} a[e0]=${anotherAddress} t[url]='${url}' c=${contenthash} xy=${concat([x, y])}`;
    const encodedRRs = encodeRRs([
      makeTXT(basicProfile.name, `ENS1 ${dnsnameResolver} ${context}`),
    ]);

    it("unsupported", async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mockDNSSEC.write.setResponse([encodedRRs]);
      await expect(
        F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(basicProfile.name),
          dummyBytes4,
        ]),
      )
        .toBeRevertedWithCustomError("UnsupportedResolverProfile") // TODO: fix after merge
        .withArgs([dummyBytes4]);
    });

    it("invalid hex", async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      const invalidHex = "!@#$";
      await F.mockDNSSEC.write.setResponse([
        encodeRRs([
          makeTXT(
            basicProfile.name,
            `ENS1 ${dnsnameResolver} a[60]=${invalidHex}`,
          ),
        ]),
      ]);
      const [res] = makeResolutions({
        name: basicProfile.name,
        addresses: [{ coinType: COIN_TYPE_ETH, value: testAddress }],
      });
      await expect(
        F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(basicProfile.name),
          res.call,
        ]),
      )
        .toBeRevertedWithCustomErrorFrom(F.dnsTXTResolver, "InvalidHexData") // TODO: fix after merge
        .withArgs([stringToHex(invalidHex)]);
    });

    it("invalid length: address", async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mockDNSSEC.write.setResponse([
        encodeRRs([
          makeTXT(
            basicProfile.name,
            `ENS1 ${dnsnameResolver} a[60]=${dummyBytes4}`,
          ),
        ]),
      ]);
      const [res] = makeResolutions({
        name: basicProfile.name,
        addresses: [{ coinType: COIN_TYPE_ETH, value: testAddress }],
      });
      await expect(
        F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(basicProfile.name),
          res.call,
        ]),
      )
        .toBeRevertedWithCustomErrorFrom(F.dnsTXTResolver, "InvalidDataLength") // TODO: fix after merge
        .withArgs([dummyBytes4, 20n]);
    });

    it("invalid length: pubkey", async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mockDNSSEC.write.setResponse([
        encodeRRs([
          makeTXT(
            basicProfile.name,
            `ENS1 ${dnsnameResolver} xy=${dummyBytes4}`,
          ),
        ]),
      ]);
      const [res] = makeResolutions({
        name: basicProfile.name,
        pubkey: { x, y },
      });
      await expect(
        F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(basicProfile.name),
          res.call,
        ]),
      )
        .toBeRevertedWithCustomErrorFrom(F.dnsTXTResolver, "InvalidDataLength") // TODO: fix after merge
        .withArgs([dummyBytes4, 64n]);
    });

    it("addr()", async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mockDNSSEC.write.setResponse([encodedRRs]);
      const [res] = makeResolutions(basicProfile);
      const [answer, resolver] =
        await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(basicProfile.name),
          res.call,
        ]);
      expectVar({ resolver }).toEqualAddress(F.dnsTLDResolver.address);
      res.expect(answer);
    });

    it("addr() w/fallback", async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mockDNSSEC.write.setResponse([encodedRRs]);
      const [res] = makeResolutions({
        name: basicProfile.name,
        addresses: [
          { coinType: COIN_TYPE_DEFAULT | 1n, value: anotherAddress },
        ],
      });
      const [answer, resolver] =
        await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(basicProfile.name),
          res.call,
        ]);
      expectVar({ resolver }).toEqualAddress(F.dnsTLDResolver.address);
      res.expect(answer);
    });

    it("hasAddr()", async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mockDNSSEC.write.setResponse([encodedRRs]);
      const bundle = bundleCalls(
        makeResolutions({
          name: basicProfile.name,
          hasAddresses: [
            { coinType: COIN_TYPE_ETH, exists: true },
            { coinType: COIN_TYPE_DEFAULT, exists: true },
            { coinType: COIN_TYPE_DEFAULT | 1n, exists: false },
          ],
        }),
      );
      const [answer, resolver] =
        await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(basicProfile.name),
          bundle.call,
        ]);
      expectVar({ resolver }).toEqualAddress(F.dnsTLDResolver.address);
      bundle.expect(answer);
    });

    it("text(url)", async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mockDNSSEC.write.setResponse([encodedRRs]);
      const [res] = makeResolutions({
        name: basicProfile.name,
        texts: [{ key: "url", value: url }],
      });
      const [answer, resolver] =
        await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(basicProfile.name),
          res.call,
        ]);
      expectVar({ resolver }).toEqualAddress(F.dnsTLDResolver.address);
      res.expect(answer);
    });

    it("contenthash()", async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mockDNSSEC.write.setResponse([encodedRRs]);
      const [res] = makeResolutions({
        name: basicProfile.name,
        contenthash: { value: contenthash },
      });
      const [answer, resolver] =
        await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(basicProfile.name),
          res.call,
        ]);
      expectVar({ resolver }).toEqualAddress(F.dnsTLDResolver.address);
      res.expect(answer);
    });

    it("pubkey()", async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mockDNSSEC.write.setResponse([encodedRRs]);
      const [res] = makeResolutions({
        name: basicProfile.name,
        pubkey: { x, y },
      });
      const [answer, resolver] =
        await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(basicProfile.name),
          res.call,
        ]);
      expectVar({ resolver }).toEqualAddress(F.dnsTLDResolver.address);
      res.expect(answer);
    });

    it("multicall", async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mockDNSSEC.write.setResponse([encodedRRs]);
      const bundle = bundleCalls(
        makeResolutions({
          name: basicProfile.name,
          addresses: [
            { coinType: COIN_TYPE_ETH, value: testAddress },
            { coinType: COIN_TYPE_DEFAULT | 1n, value: anotherAddress },
            { coinType: COIN_TYPE_DEFAULT | 2n, value: anotherAddress },
          ],
          texts: [{ key: "url", value: url }],
          contenthash: { value: contenthash },
          pubkey: { x, y },
        }),
      );
      const [answer, resolver] =
        await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(basicProfile.name),
          bundle.call,
        ]);
      expectVar({ resolver }).toEqualAddress(F.dnsTLDResolver.address);
      bundle.expect(answer);
    });

    const TEXT_DNSSEC_CONTEXT = "eth.ens.dnssec-context";
    it(`text(${TEXT_DNSSEC_CONTEXT})`, async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mockDNSSEC.write.setResponse([encodedRRs]);
      const [res] = makeResolutions({
        name: basicProfile.name,
        texts: [{ key: TEXT_DNSSEC_CONTEXT, value: context }],
      });
      const [answer, resolver] =
        await F.mainnetV2.universalResolver.read.resolve([
          dnsEncodeName(basicProfile.name),
          res.call,
        ]);
      expectVar({ resolver }).toEqualAddress(F.dnsTLDResolver.address);
      res.expect(answer);
    });
  });
});
