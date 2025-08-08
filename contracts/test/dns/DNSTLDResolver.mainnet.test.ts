import hre from "hardhat";
import { describe, it } from "vitest";
import { namehash } from "viem";
import { dnsEncodeName, getLabelAt } from "../utils/utils.js";
import { deployV2Fixture } from "../fixtures/deployV2Fixture.js";
import { expectVar } from "../utils/expectVar.ts";
import {
  COIN_TYPE_ETH,
  KnownProfile,
  bundleCalls,
  makeResolutions,
} from "../utils/resolutions.js";

const KNOWN: KnownProfile[] = [
  {
    name: "taytems.xyz",
    addresses: [
      {
        coinType: COIN_TYPE_ETH,
        value: "0x8e8Db5CcEF88cca9d624701Db544989C996E3216",
      },
    ],
  },
  {
    name: "raffy.xyz",
    texts: [{ key: "avatar", value: "https://raffy.xyz/ens.jpg" }],
    addresses: [
      {
        coinType: COIN_TYPE_ETH,
        value: "0x51050ec063d393217B436747617aD1C2285Aeeee",
      },
    ],
  },
];

const url = await (async (config) => {
  return config.type === "http" && config.url.get();
})(hre.config.networks.mainnet).catch(() => {});

let tests = () => {};
if (url) {
  const chain = await hre.network.connect({
    override: { forking: { enabled: true, url } },
  });

  async function fixture() {
    await chain.networkHelpers.mine(); // https://github.com/NomicFoundation/hardhat/issues/5511#issuecomment-2288072104
    const mainnetV2 = await deployV2Fixture(chain, true); // CCIP on UR
    const ensRegistry = await chain.viem.getContractAt(
      "ENSRegistry",
      "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e",
    );
    const dnsTLDResolverV1 = await chain.viem.getContractAt(
      "OffchainDNSResolver",
      await ensRegistry.read.resolver([namehash("com")]),
    );
    const DNSSEC = await chain.viem.getContractAt(
      "DNSSEC",
      await dnsTLDResolverV1.read.oracle(),
    );
    const dnsTLDResolver = await chain.viem.deployContract("DNSTLDResolver", [
      ensRegistry.address,
      dnsTLDResolverV1.address,
      mainnetV2.rootRegistry.address,
      DNSSEC.address,
      [await dnsTLDResolverV1.read.gatewayURL()],
      ["x-batch-gateway:true"],
    ]);
    for (const name of ["dnsname.ens.eth"]) {
      await mainnetV2.setupName({
        name,
        resolverAddress: await ensRegistry.read.resolver([namehash(name)]),
      });
    }
    return {
      ensRegistry,
      dnsTLDResolverV1,
      DNSSEC,
      mainnetV2,
      dnsTLDResolver,
    };
  }

  tests = () => {
    const timeout = 15000;
    describe("v1", () => {
      for (const kp of KNOWN) {
        it(kp.name, { timeout }, async () => {
          const F = await chain.networkHelpers.loadFixture(fixture);
          await F.mainnetV2.setupName({
            name: getLabelAt(kp.name, -1),
            resolverAddress: F.dnsTLDResolverV1.address,
          });
          const bundle = bundleCalls(makeResolutions(kp));
          const [answer, resolver] =
            await F.mainnetV2.universalResolver.read.resolve([
              dnsEncodeName(kp.name),
              bundle.call,
            ]);
          expectVar({ resolver }).toEqualAddress(F.dnsTLDResolverV1.address);
          bundle.expect(answer);
        });
      }
    });
    describe("v2", () => {
      for (const kp of KNOWN) {
        it(kp.name, { timeout }, async () => {
          const F = await chain.networkHelpers.loadFixture(fixture);
          await F.mainnetV2.setupName({
            name: getLabelAt(kp.name, -1),
            resolverAddress: F.dnsTLDResolver.address,
          });
          const bundle = bundleCalls(makeResolutions(kp));
          const [answer, resolver] =
            await F.mainnetV2.universalResolver.read.resolve([
              dnsEncodeName(kp.name),
              bundle.call,
            ]);
          expectVar({ resolver }).toEqualAddress(F.dnsTLDResolver.address);
          bundle.expect(answer);
        });
      }
    });
  };
}

describe.skipIf(!url)("DNSTLDResolver (mainnet)", tests);
