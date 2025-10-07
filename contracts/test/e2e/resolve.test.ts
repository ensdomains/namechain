import {
  describe,
  it,
  expect,
  beforeAll,
  beforeEach,
  afterAll,
} from "bun:test";
import {
  type Address,
  getAddress,
  labelhash,
  namehash,
  toHex,
  zeroAddress,
} from "viem";

import {
  type CrossChainEnvironment,
  CrosschainSnapshot,
  setupCrossChainEnvironment,
} from "../../script/setup.js";
import { dnsEncodeName } from "../utils/utils.js";
import {
  COIN_TYPE_ETH,
  COIN_TYPE_DEFAULT,
  type KnownProfile,
  makeResolutions,
  bundleCalls,
  getReverseName,
} from "../utils/resolutions.js";
import { MAX_EXPIRY } from "../../deploy/constants.js";
import { expectVar } from "../utils/expectVar.js";

describe("Resolve", () => {
  let env: CrossChainEnvironment;
  let resetState: CrosschainSnapshot;
  beforeAll(async () => {
    env = await setupCrossChainEnvironment();
    resetState = await env.saveState();
  });
  afterAll(() => env?.shutdown());
  beforeEach(() => resetState?.());

  async function expectResolve(kp: KnownProfile) {
    const bundle = bundleCalls(makeResolutions(kp));
    const [answer] = await env.l1.contracts.UniversalResolverV2.read.resolve([
      dnsEncodeName(kp.name),
      bundle.call,
    ]);
    bundle.expect(answer);
  }

  it("state", async () => {
    const address = toHex(1, { size: 20 });
    const slot = toHex(0, { size: 32 });
    await env.l1.client.setStorageAt({
      address,
      index: Number(slot),
      value: toHex(1, { size: 32 }),
    });
    expect(
      env.l1.client.getStorageAt({ address, slot }),
    ).resolves.toStrictEqual(toHex(1, { size: 32 }));
    await resetState();
    expect(
      env.l1.client.getStorageAt({ address, slot }),
    ).resolves.toStrictEqual(toHex(0, { size: 32 }));
  });

  describe("Protocol", () => {
    async function named(name: string, fn: () => Address) {
      it(name, async () => {
        const [resolver] =
          await env.l1.contracts.UniversalResolverV2.read.findResolver([
            dnsEncodeName(name),
          ]);
        expectVar({ resolver }).toStrictEqual(getAddress(fn())); // toEqualAddress
      });
    }

    named("eth", () => env.l1.contracts.ETHTLDResolver.address);
    named("reverse", () => env.l1.contracts.DefaultReverseResolver.address);
    named("addr.reverse", () => env.l1.contracts.ETHReverseResolver.address);
  });

  describe("L1", () => {
    it("eth + addr() => ETHTLDResolver", () =>
      expectResolve({
        name: "eth",
        addresses: [
          {
            coinType: COIN_TYPE_ETH,
            value: env.l1.contracts.ETHTLDResolver.address,
          },
        ],
      }));

    it("dnsname.ens.eth + addr() => DNSTXTResolver", () =>
      expectResolve({
        name: "dnsname.ens.eth",
        addresses: [
          {
            coinType: COIN_TYPE_ETH,
            value: env.l1.contracts.DNSTXTResolver.address,
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
        await env.l1.contracts.ETHRegistrarV1.write.addController(
          [owner.address],
          { account: owner },
        );
        // hack: direct register
        await env.l1.contracts.ETHRegistrarV1.write.register(
          [BigInt(labelhash(label)), account.address, MAX_EXPIRY],
          { account: owner },
        );
        // setup addr(60)
        await env.l1.contracts.PublicResolverV1.write.setAddr(
          [namehash(name), COIN_TYPE_ETH, account.address],
          { account },
        );
        // set resolver
        await env.l1.contracts.ENSRegistryV1.write.setResolver(
          [namehash(name), env.l1.contracts.PublicResolverV1.address],
          { account },
        );
        // setup name()
        await env.l1.contracts.ReverseRegistrarV1.write.setName([name], {
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
        const [primary] =
          await env.l1.contracts.UniversalResolverV2.read.reverse([
            account.address,
            COIN_TYPE_ETH,
          ]);
        expectVar({ primary }).toStrictEqual(name);
      });

      it("addr.reverse", async () => {
        const { deployer, owner: account } = env.namedAccounts;

        // setup addr(default)
        const resolver = await env.l1.deployDedicatedResolver(account);
        await resolver.write.setAddr([COIN_TYPE_ETH, account.address]);
        // hack: create name
        await env.l1.contracts.ETHRegistry.write.register(
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
        await env.l1.contracts.ETHReverseRegistrar.write.setName([name], {
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
        const [primary] =
          await env.l1.contracts.UniversalResolverV2.read.reverse([
            account.address,
            COIN_TYPE_ETH,
          ]);
        expectVar({ primary }).toStrictEqual(name);
      });

      it("default.reverse", async () => {
        const { deployer, owner: account } = env.namedAccounts;

        // setup addr(default)
        const resolver = await env.l1.deployDedicatedResolver(account);
        await resolver.write.setAddr([COIN_TYPE_DEFAULT, account.address]);
        // hack: create name
        await env.l1.contracts.ETHRegistry.write.register(
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
        await env.l1.contracts.DefaultReverseRegistrar.write.setName([name], {
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
        const [primary] =
          await env.l1.contracts.UniversalResolverV2.read.reverse([
            account.address,
            COIN_TYPE_ETH,
          ]);
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
            value: env.l1.contracts.ETHTLDResolver.address,
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
            value: env.l1.contracts.DNSTXTResolver.address,
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

        await env.l2.contracts.ETHRegistry.write.register([
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
