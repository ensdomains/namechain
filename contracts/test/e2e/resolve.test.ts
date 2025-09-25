import {
  afterAll,
  beforeAll,
  beforeEach,
  describe,
  expect,
  it,
} from "bun:test";
import {
  type Address,
  getAddress,
  labelhash,
  namehash,
  zeroAddress,
} from "viem";

import { MAX_EXPIRY } from "../../deploy/constants.ts";
import {
  type CrossChainEnvironment,
  setupCrossChainEnvironment,
} from "../../script/setup.ts";
import { expectVar } from "../integration/test-utils/expectVar.ts";
import {
  bundleCalls,
  COIN_TYPE_DEFAULT,
  COIN_TYPE_ETH,
  getReverseName,
  type KnownProfile,
  makeResolutions,
} from "../integration/test-utils/resolutions.ts";
import { dnsEncodeName } from "../integration/test-utils/utils.ts";

describe("Resolve", () => {
  let env: CrossChainEnvironment;
  beforeAll(async () => {
    env = await setupCrossChainEnvironment();
  });
  afterAll(() => env?.shutdown());
  beforeEach(() => env?.resetState());

  async function expectResolve(kp: KnownProfile) {
    const bundle = bundleCalls(makeResolutions(kp));
    const [answer] = await env.l1.contracts.universalResolver.read.resolve([
      dnsEncodeName(kp.name),
      bundle.call,
    ]);
    bundle.expect(answer);
  }

  it("state", async () => {
    const b0 = await env.l1.client.getBlockNumber();
    await env.sync();
    const b1 = await env.l1.client.getBlockNumber();
    expect(b1, "mine").toStrictEqual(b0 + 1n);
    await env.resetState();
    const b2 = await env.l1.client.getBlockNumber();
    expect(b2, "reset").toStrictEqual(b0);
  });

  describe("Protocol", () => {
    async function named(name: string, fn: () => Address) {
      it(name, async () => {
        const [resolver] =
          await env.l1.contracts.universalResolver.read.findResolver([
            dnsEncodeName(name),
          ]);
        expectVar({ resolver }).toStrictEqual(getAddress(fn())); // toEqualAddress
      });
    }

    named("eth", () => env.l1.contracts.ethTLDResolver.address);
    named("reverse", () => env.l1.contracts.defaultReverseResolver.address);
    named("addr.reverse", () => env.l1.contracts.ethReverseResolver.address);
  });

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
    describe("addr.reverse", () => {
      const label = "user";
      const name = `${label}.eth`;

      it("addr.reverse w/fallback to v1", async () => {
        const { owner, user: account } = env.namedAccounts;

        // hack: eoa controller
        await env.l1.contracts.ethRegistrarV1.write.addController(
          [owner.address],
          { account: owner },
        );
        // hack: direct register
        await env.l1.contracts.ethRegistrarV1.write.register(
          [BigInt(labelhash(label)), account.address, MAX_EXPIRY],
          { account: owner },
        );
        // setup addr(60)
        await env.l1.contracts.publicResolverV1.write.setAddr(
          [namehash(name), COIN_TYPE_ETH, account.address],
          { account },
        );
        // set resolver
        await env.l1.contracts.ensRegistryV1.write.setResolver(
          [namehash(name), env.l1.contracts.publicResolverV1.address],
          { account },
        );
        // setup name()
        await env.l1.contracts.reverseRegistrarV1.write.setName([name], {
          account,
        });

        await expectResolve({
          name: getReverseName(account.address),
          primary: { value: name },
        });
        await expectResolve({
          name,
          addresses: [{ coinType: COIN_TYPE_ETH, value: account.address }],
        });
        const [primary] = await env.l1.contracts.universalResolver.read.reverse(
          [account.address, COIN_TYPE_ETH],
        );
        expectVar({ primary }).toStrictEqual(name);
      });

      it("addr.reverse", async () => {
        const { deployer, owner: account } = env.namedAccounts;

        // setup addr(default)
        const resolver = await env.l1.deployDedicatedResolver(account);
        await resolver.write.setAddr([COIN_TYPE_ETH, account.address]);
        // hack: create name
        await env.l1.contracts.ethRegistry.write.register(
          [
            label,
            account.address,
            zeroAddress,
            resolver.address,
            0n,
            MAX_EXPIRY,
          ],
          { account: deployer },
        );
        // setup name()
        await env.l1.contracts.ethReverseRegistrar.write.setName([name], {
          account,
        });

        await expectResolve({
          name: getReverseName(account.address),
          primary: { value: name },
        });
        await expectResolve({
          name,
          addresses: [{ coinType: COIN_TYPE_ETH, value: account.address }],
        });
        const [primary] = await env.l1.contracts.universalResolver.read.reverse(
          [account.address, COIN_TYPE_ETH],
        );
        expectVar({ primary }).toStrictEqual(name);
      });

      it("default.reverse", async () => {
        const { deployer, owner: account } = env.namedAccounts;

        // setup addr(default)
        const resolver = await env.l1.deployDedicatedResolver(account);
        await resolver.write.setAddr([COIN_TYPE_DEFAULT, account.address]);
        // hack: create name
        await env.l1.contracts.ethRegistry.write.register(
          [
            label,
            account.address,
            zeroAddress,
            resolver.address,
            0n,
            MAX_EXPIRY,
          ],
          { account: deployer },
        );
        // setup name()
        await env.l1.contracts.defaultReverseRegistrar.write.setName([name], {
          account,
        });

        await expectResolve({
          name: getReverseName(account.address, COIN_TYPE_DEFAULT),
          primary: { value: name },
        });
        await expectResolve({
          name,
          addresses: [{ coinType: COIN_TYPE_ETH, value: account.address }],
        });
        const [primary] = await env.l1.contracts.universalResolver.read.reverse(
          [account.address, COIN_TYPE_ETH],
        );
        expectVar({ primary }).toStrictEqual(name);
      });
    });
  });

  describe("DNS", () => {
    it("onchain txt: dnstxt.raffy.xyz", () =>
      // `dnsname.ens.eth t[avatar]=https://raffy.xyz/ens.jpg a[e0]=0x51050ec063d393217B436747617aD1C2285Aeeee`
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
      // `dnsalias.ens.eth eth`
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
      // `dnsalias.ens.eth raffy.xyz ens.eth`
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
    function register(set: Omit<KnownProfile, "name">, get = set) {
      const label = "urg-test";
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
          MAX_EXPIRY,
        ]);

        await env.sync();
        await expectResolve({ name, ...gets });
      });
    }

    register({
      texts: [{ key: "avatar", value: "chonker.jpg" }],
    });

    register({
      addresses: [
        {
          coinType: COIN_TYPE_ETH,
          value: "0x51050ec063d393217B436747617aD1C2285Aeeee",
        },
      ],
    });

    register({
      texts: [{ key: "url", value: "https://ens.domains" }],
      contenthash: { value: "0x1234" },
      addresses: [
        {
          coinType: COIN_TYPE_ETH,
          value: "0x51050ec063d393217B436747617aD1C2285Aeeee",
        },
      ],
    });

    register(
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
