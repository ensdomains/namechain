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
    name: "brantly.cash",
    texts: [{ key: "com.twitter", value: "brantlymillegan" }],
  },
  {
    name: "raffy.xyz",
    addresses: [
      {
        coinType: COIN_TYPE_ETH,
        value: "0x51050ec063d393217B436747617aD1C2285Aeeee",
      },
    ],
  },
];

const url =
  hre.config.networks.mainnet.type === "http" &&
  (await hre.config.networks.mainnet.url.get());

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
    for (const name of new Set(KNOWN.map((x) => getLabelAt(x.name, -1)))) {
      await mainnetV2.setupName({
        name,
        resolverAddress: dnsTLDResolver.address,
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
    for (const kp of KNOWN) {
      it(kp.name, async () => {
        const F = await chain.networkHelpers.loadFixture(fixture);
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
  };
}

describe.skipIf(!url)("DNSTLDResolver (mainnet)", tests);
