import hre from "hardhat";
import { describe, expect, it } from "vitest";
import { concat, encodeErrorResult, stringToHex } from "viem";
import { shouldSupportInterfaces } from "@ensdomains/hardhat-chai-matchers-viem/behaviour";

import { shouldSupportFeatures } from "../utils/supportsFeatures.js";
import { deployV1Fixture } from "../fixtures/deployV1Fixture.js";
import { deployV2Fixture } from "../fixtures/deployV2Fixture.js";
import { expectVar } from "../utils/expectVar.ts";
import {
  type KnownProfile,
  bundleCalls,
  COIN_TYPE_DEFAULT,
  COIN_TYPE_ETH,
  makeResolutions,
} from "../utils/resolutions.js";
import { dnsEncodeName } from "../utils/utils.js";
import { encodeRRs, makeTXT } from "./rr.js";

const chain = await hre.network.connect();

const dnsnameResolver = "dnsname.ens.eth";
const dummyBytes4 = "0x12345678";
const testAddress = "0x8000000000000000000000000000000000000001";
const basicProfile: KnownProfile = {
  name: "test.com",
  addresses: [{ coinType: COIN_TYPE_ETH, value: testAddress }],
};

// sufficient to satisfy: `abi.decode(DNSSEC.RRSetWithSignature[])`
const dnsOracleGateway =
  'data:application/json,{"data":"0x0000000000000000000000000000000000000000000000000000000000000000"}';

async function fixture() {
  const mainnetV1 = await deployV1Fixture(chain);
  const mainnetV2 = await deployV2Fixture(chain, true); // CCIP on UR
  const ssResolver = await chain.viem.deployContract("DummyShapeshiftResolver");
  const mockDNSSEC = await chain.viem.deployContract("MockDNSSEC");
  const dnsTLDResolverV1 = await chain.viem.deployContract(
    "OffchainDNSResolver",
    [mainnetV1.ensRegistry.address, mockDNSSEC.address, dnsOracleGateway],
  );
  const oracleGatewayProvider = await chain.viem.deployContract(
    "GatewayProvider",
    [[dnsOracleGateway]],
  );
  const dnsTLDResolver = await chain.viem.deployContract("DNSTLDResolver", [
    mainnetV1.ensRegistry.address,
    dnsTLDResolverV1.address,
    mainnetV2.rootRegistry.address,
    mockDNSSEC.address,
    oracleGatewayProvider.address,
    mainnetV2.batchGatewayProvider.address,
  ]);
  await mainnetV1.setupName({
    name: "com",
    resolverAddress: dnsTLDResolverV1.address,
  });
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
    dnsTLDResolverV1,
    oracleGatewayProvider,
    dnsTLDResolver,
    dnsTXTResolver,
    async expectGasless(kp: KnownProfile) {
      const bundle = bundleCalls(makeResolutions(kp));
      const [answer, resolver] = await mainnetV2.universalResolver.read.resolve(
        [dnsEncodeName(kp.name), bundle.call],
      );
      expectVar({ resolver }).toEqualAddress(dnsTLDResolver.address);
      bundle.expect(answer);
      const directAnswer = await dnsTLDResolver.read.resolve([
        dnsEncodeName(kp.name),
        bundle.call,
      ]);
      expectVar({ directAnswer }).toStrictEqual(answer);
    },
  };
}

describe("DNSTLDResolver", () => {
  shouldSupportInterfaces({
    contract: () =>
      chain.networkHelpers.loadFixture(fixture).then((F) => F.dnsTLDResolver),
    interfaces: ["IERC165", "IExtendedResolver", "IFeatureSupporter"],
  });

  shouldSupportFeatures({
    contract: () =>
      chain.networkHelpers.loadFixture(fixture).then((F) => F.dnsTLDResolver),
    features: {
      RESOLVER: ["RESOLVE_MULTICALL"],
    },
  });

  function testProfiles(
    name: string,
    factory: (kp: KnownProfile) => () => Promise<void>,
    testFn: typeof it.only = it,
  ) {
    testFn(name, factory(basicProfile));
    testFn(
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
      for (const res of makeResolutions(kp)) {
        await F.mainnetV1.publicResolver.write.multicall([[res.write]]);
      }
      await F.expectGasless(kp);
    });

    testProfiles("onchain extended", (kp) => async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mainnetV1.setupName({
        name: kp.name,
        resolverAddress: F.ssResolver.address,
      });
      await F.ssResolver.write.setExtended([true]);
      for (const res of makeResolutions(kp)) {
        await F.ssResolver.write.setResponse([res.call, res.answer]);
      }
      await F.expectGasless(kp);
    });

    testProfiles("offchain extended", (kp) => async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mainnetV1.setupName({
        name: kp.name,
        resolverAddress: F.ssResolver.address,
      });
      await F.ssResolver.write.setExtended([true]);
      await F.ssResolver.write.setOffchain([true]);
      for (const res of makeResolutions(kp)) {
        await F.ssResolver.write.setResponse([res.call, res.answer]);
      }
      await F.expectGasless(kp);
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
        .toBeRevertedWithCustomError("ResolverError")
        .withArgs([
          encodeErrorResult({
            abi: F.dnsTLDResolver.abi,
            errorName: "UnreachableName",
            args: [dnsEncodeName(basicProfile.name)],
          }),
        ]);
    });

    describe("via address", () => {
      testProfiles("onchain immediate", (kp) => async () => {
        const F = await chain.networkHelpers.loadFixture(fixture);
        await F.mockDNSSEC.write.setResponse([
          encodeRRs([
            makeTXT(kp.name, `ENS1 ${F.mainnetV2.dedicatedResolver.address}`),
          ]),
        ]);
        await F.mainnetV2.dedicatedResolver.write.multicall([
          makeResolutions(kp).map((x) => x.writeDedicated),
        ]);
        await F.expectGasless(kp);
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
        for (const res of makeResolutions(kp)) {
          await F.ssResolver.write.setResponse([res.call, res.answer]);
        }
        await F.mockDNSSEC.write.setResponse([
          encodeRRs([makeTXT(kp.name, `ENS1 ${name}`)]),
        ]);
        await F.expectGasless(kp);
      });

      testProfiles("offchain extended", (kp) => async () => {
        const F = await chain.networkHelpers.loadFixture(fixture);
        const name = "myresolver.eth";
        await F.mainnetV2.setupName({
          name,
          resolverAddress: F.ssResolver.address,
        });
        await F.ssResolver.write.setExtended([true]);
        await F.ssResolver.write.setOffchain([true]);
        for (const res of makeResolutions(kp)) {
          await F.ssResolver.write.setResponse([res.call, res.answer]);
        }
        await F.mockDNSSEC.write.setResponse([
          encodeRRs([makeTXT(kp.name, `ENS1 ${name}`)]),
        ]);
        await F.expectGasless(kp);
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
        .toBeRevertedWithCustomError("UnsupportedResolverProfile")
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
        .toBeRevertedWithCustomError("ResolverError")
        .withArgs([
          encodeErrorResult({
            abi: F.dnsTXTResolver.abi,
            errorName: "InvalidHexData",
            args: [stringToHex(invalidHex)],
          }),
        ]);
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
        .toBeRevertedWithCustomError("ResolverError")
        .withArgs([
          encodeErrorResult({
            abi: F.dnsTXTResolver.abi,
            errorName: "InvalidDataLength",
            args: [dummyBytes4, 20n],
          }),
        ]);
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
        .toBeRevertedWithCustomError("ResolverError")
        .withArgs([
          encodeErrorResult({
            abi: F.dnsTXTResolver.abi,
            errorName: "InvalidDataLength",
            args: [dummyBytes4, 64n],
          }),
        ]);
    });

    it("addr()", async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mockDNSSEC.write.setResponse([encodedRRs]);
      await F.expectGasless(basicProfile);
    });

    it("addr() w/fallback", async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mockDNSSEC.write.setResponse([encodedRRs]);
      await F.expectGasless({
        name: basicProfile.name,
        addresses: [
          { coinType: COIN_TYPE_DEFAULT | 1n, value: anotherAddress },
        ],
      });
    });

    it("hasAddr()", async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mockDNSSEC.write.setResponse([encodedRRs]);
      await F.expectGasless({
        name: basicProfile.name,
        hasAddresses: [
          { coinType: COIN_TYPE_ETH, exists: true },
          { coinType: COIN_TYPE_DEFAULT, exists: true },
          { coinType: COIN_TYPE_DEFAULT | 1n, exists: false },
        ],
      });
    });

    it("text(url)", async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mockDNSSEC.write.setResponse([encodedRRs]);
      await F.expectGasless({
        name: basicProfile.name,
        texts: [{ key: "url", value: url }],
      });
    });

    it("contenthash()", async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mockDNSSEC.write.setResponse([encodedRRs]);
      await F.expectGasless({
        name: basicProfile.name,
        contenthash: { value: contenthash },
      });
    });

    it("pubkey()", async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mockDNSSEC.write.setResponse([encodedRRs]);
      await F.expectGasless({
        name: basicProfile.name,
        pubkey: { x, y },
      });
    });

    it("multicall", async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mockDNSSEC.write.setResponse([encodedRRs]);
      await F.expectGasless({
        name: basicProfile.name,
        addresses: [
          { coinType: COIN_TYPE_ETH, value: testAddress },
          { coinType: COIN_TYPE_DEFAULT | 1n, value: anotherAddress },
          { coinType: COIN_TYPE_DEFAULT | 2n, value: anotherAddress },
        ],
        texts: [{ key: "url", value: url }],
        contenthash: { value: contenthash },
        pubkey: { x, y },
      });
    });

    const TEXT_DNSSEC_CONTEXT = "eth.ens.dnssec-context";
    it(`text(${TEXT_DNSSEC_CONTEXT})`, async () => {
      const F = await chain.networkHelpers.loadFixture(fixture);
      await F.mockDNSSEC.write.setResponse([encodedRRs]);
      await F.expectGasless({
        name: basicProfile.name,
        texts: [{ key: TEXT_DNSSEC_CONTEXT, value: context }],
      });
    });
  });
});
