import { describe, it, beforeAll, afterAll } from "vitest";
import { labelhash, namehash, zeroAddress } from "viem";

import { setupCrossChainEnvironment } from "../script/setup.ts";
import { dnsEncodeName } from "../test/utils/utils.ts";
import {
  COIN_TYPE_ETH,
  COIN_TYPE_DEFAULT,
  type KnownProfile,
  makeResolutions,
  bundleCalls,
  KnownReverse,
} from "../test/utils/resolutions.ts";
import { MAX_EXPIRY } from "../deploy/constants.ts";
import { expectVar } from "../test/utils/expectVar.ts";

type UnnamedProfile = Omit<KnownProfile, "name">;

describe("Resolve", () => {
  let env: Awaited<ReturnType<typeof setupCrossChainEnvironment>>;
  beforeAll(async () => {
    env = await setupCrossChainEnvironment();
  });
  afterAll(() => env?.shutdown());

  async function expectResolve(kp: KnownProfile) {
    const bundle = bundleCalls(makeResolutions(kp));
    const [answer] = await env.l1.contracts.universalResolver.read.resolve([
      dnsEncodeName(kp.name),
      bundle.call,
    ]);
    bundle.expect(answer);
  }

  // async function expectReverse(kp: KnownReverse) {
  //   const bundle = bundleCalls(makeResolutions(kp));
  //   const [primary] = await env.l1.contracts.universalResolver.read.reverse([
  //     kp.encodedAddress,
  //     kp.coinType,
  //   ]);
  // }

  describe("L1", () => {
    it("eth + addr() => ETHTLDResolver", () =>
      expectResolve({
        name: "eth",
        addresses: [
          {
            coinType: COIN_TYPE_ETH,
            value: env.l1.contracts.ethTLDResolver.address,
          },
        ],
      }));

    it("addr.reverse + addr() => DNSTXTResolver", () =>
      expectResolve({
        name: "dnsname.ens.eth",
        addresses: [
          {
            coinType: COIN_TYPE_ETH,
            value: env.l1.contracts.dnsTXTResolver.address,
          },
        ],
      }));

    it("dnsname.ens.eth + addr() => DNSTXTResolver", () =>
      expectResolve({
        name: "dnsname.ens.eth",
        addresses: [
          {
            coinType: COIN_TYPE_ETH,
            value: env.l1.contracts.dnsTXTResolver.address,
          },
        ],
      }));
  });

  describe("Reverse", () => {
    it("*.addr.reverse fallback to v1", async () => {
      const label = "deployer";
      const name = `${label}.eth`;
      const { owner, deployer } = env.namedAccounts;

      // become eoa controller
      await env.l1.contracts.ethRegistrarV1.write.addController(
        [owner.address],
        { account: owner },
      );
      // direct register
      await env.l1.contracts.ethRegistrarV1.write.register(
        [BigInt(labelhash(label)), deployer.address, MAX_EXPIRY],
        { account: owner },
      );
      /*
      // hack in "deployer.eth"
      await env.l1.contracts.ensRegistryV1.write.setSubnodeRecord(
        [
          namehash("eth"),
          labelhash(label),
          deployer.address,
          env.l1.contracts.publicResolverV1.address,
          0n,
        ],
        { account: owner },
      );
      */
      // create addr(60)
      await env.l1.contracts.publicResolverV1.write.setAddr(
        [namehash(name), COIN_TYPE_ETH, deployer.address],
        { account: deployer },
      );

      console.log('default:', await env.l1.contracts.reverseRegistrarV1.read.defaultResolver());

      // create name() [TODO: defaultResolver() not set]
      await env.l1.contracts.reverseRegistrarV1.write.setNameForAddr(
        [
          deployer.address,
          deployer.address,
          env.l1.contracts.publicResolverV1.address,
          name,
        ],
        { account: deployer },
      );

      await expectResolve({
        name,
        addresses: [
          {
            coinType: COIN_TYPE_ETH,
            value: deployer.address
          }
        ]
      })


      // resolve it
      const [primary, resolver, reverseResolver] =
        await env.l1.contracts.universalResolver.read.reverse([
          deployer.address,
          COIN_TYPE_ETH,
        ]);
      expectVar({ primary }).toStrictEqual(name);
      expectVar({ resolver }).toEqualAddress(
        env.l1.contracts.publicResolverV1.address,
      );
      expectVar({ reverseResolver }).toEqualAddress(
        env.l1.contracts.ethReverseResolver.address,
      );
    });

    it("*.addr.reverse in v2", async () => {});
  });

  describe("DNS", () => {
    it("onchain txt: dnstxt.raffy.xyz", () =>
      expectResolve({
        name: "dnstxt.raffy.xyz",
        addresses: [
          {
            coinType: COIN_TYPE_ETH,
            value: "0x51050ec063d393217B436747617aD1C2285Aeeee",
          },
        ],
        texts: [{ key: "avatar", value: "https://raffy.xyz/ens.jpg" }],
      }));

    it("alias replace: dnsalias.raffy.xyz => eth", () =>
      expectResolve({
        name: "dnsalias.raffy.xyz",
        addresses: [
          {
            coinType: COIN_TYPE_ETH,
            value: env.l1.contracts.ethTLDResolver.address,
          },
        ],
      }));

    it("alias rewrite: dnsname[.raffy.xyz] => dnsname[.ens.eth]", () =>
      expectResolve({
        name: "dnsname.raffy.xyz",
        addresses: [
          {
            coinType: COIN_TYPE_ETH,
            value: env.l1.contracts.dnsTXTResolver.address,
          },
        ],
      }));
  });

  describe("L2", () => {
    let count = 0;
    function testRegisterL2AndResolve(set: UnnamedProfile, get = set) {
      const label = `urg-test-${count++}`;
      const name = `${label}.eth`;
      const sets = makeResolutions({ ...set, name });
      const gets = makeResolutions({ ...get, name });
      let title = `${sets.map((x) => x.desc)}`;
      if (get !== set) {
        title = `${title} => ${gets.map((x) => x.desc)}`;
      }
      it(title, async () => {
        const { owner } = env.namedAccounts;

        const resolver = await env.l2.deployDedicatedResolver(owner);
        await resolver.write.multicall([sets.map((x) => x.writeDedicated)]);

        await env.l2.contracts.ethRegistry.write.register([
          label,
          owner.address,
          zeroAddress,
          resolver.address,
          0n,
          BigInt(Math.floor(Date.now() / 1000) + 10000),
        ]);

        await env.sync();
        await expectResolve({ name, ...gets });
      });
    }

    testRegisterL2AndResolve({
      texts: [{ key: "avatar", value: "chonker.jpg" }],
    });

    testRegisterL2AndResolve({
      addresses: [
        {
          coinType: COIN_TYPE_ETH,
          value: "0x51050ec063d393217B436747617aD1C2285Aeeee",
        },
      ],
    });

    testRegisterL2AndResolve({
      texts: [{ key: "url", value: "https://ens.domains" }],
      contenthash: { value: "0x1234" },
      addresses: [
        {
          coinType: COIN_TYPE_ETH,
          value: "0x51050ec063d393217B436747617aD1C2285Aeeee",
        },
      ],
    });

    testRegisterL2AndResolve(
      {
        addresses: [
          {
            coinType: COIN_TYPE_DEFAULT,
            value: "0x51050ec063d393217B436747617aD1C2285Aeeee",
          },
        ],
      },
      {
        addresses: [
          {
            coinType: COIN_TYPE_ETH,
            value: "0x51050ec063d393217B436747617aD1C2285Aeeee",
          },
          {
            coinType: COIN_TYPE_DEFAULT | 1n,
            value: "0x51050ec063d393217B436747617aD1C2285Aeeee",
          },
        ],
      },
    );
  });
});
