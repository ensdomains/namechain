import { describe, it, beforeAll, afterAll } from "vitest";
import { zeroAddress } from "viem";

import { setupCrossChainEnvironment } from "../script/setup.ts";
import { dnsEncodeName } from "../test/utils/utils.ts";
import {
  COIN_TYPE_ETH,
  COIN_TYPE_DEFAULT,
  type KnownProfile,
  makeResolutions,
  bundleCalls,
} from "../test/utils/resolutions.ts";

type UnnamedProfile = Omit<KnownProfile, "name">;

describe("Resolve", () => {
  let env: Awaited<ReturnType<typeof setupCrossChainEnvironment>>;
  beforeAll(async () => {
    env = await setupCrossChainEnvironment();
  });
  afterAll(() => env?.shutdown());

  describe("L1", () => {
    const KNOWN: Record<string, () => UnnamedProfile> = {
      eth: () => ({
        addresses: [
          {
            coinType: COIN_TYPE_ETH,
            value: env.l1.contracts.ethTLDResolver.address,
          },
        ],
      }),
      "dnsname.ens.eth": () => ({
        addresses: [
          {
            coinType: COIN_TYPE_ETH,
            value: env.l1.contracts.dnsTXTResolver.address,
          },
        ],
      }),
    };
    for (const [name, fn] of Object.entries(KNOWN)) {
      it(name, async () => {
        const bundle = bundleCalls(makeResolutions({ name, ...fn() }));
        const [answer] = await env.l1.contracts.universalResolver.read.resolve([
          dnsEncodeName(name),
          bundle.call,
        ]);
        bundle.expect(answer);
      });
    }
  });

  describe("DNS", () => {
    function resolve(kp: KnownProfile) {
      it(kp.name, async () => {
        const bundle = bundleCalls(makeResolutions(kp));
        const [answer] = await env.l1.contracts.universalResolver.read.resolve([
          dnsEncodeName(kp.name),
          bundle.call,
        ]);
        bundle.expect(answer);
      });
    }

    resolve({
      name: "namechain.raffy.xyz",
      addresses: [
        {
          coinType: COIN_TYPE_ETH,
          value: "0x51050ec063d393217B436747617aD1C2285Aeeee",
        },
      ],
      texts: [{ key: "avatar", value: "https://raffy.xyz/ens.jpg" }],
    });
  });

  describe("L2", () => {
    let count = 0;
    function resolve(set: UnnamedProfile, get = set) {
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
        const bundle = bundleCalls(gets);
        const [answer] = await env.l1.contracts.universalResolver.read.resolve([
          dnsEncodeName(name),
          bundle.call,
        ]);
        bundle.expect(answer);
      });
    }

    resolve({ texts: [{ key: "avatar", value: "chonker.jpg" }] });

    resolve({
      addresses: [
        {
          coinType: COIN_TYPE_ETH,
          value: "0x51050ec063d393217B436747617aD1C2285Aeeee",
        },
      ],
    });

    resolve({
      texts: [{ key: "url", value: "https://ens.domains" }],
      contenthash: { value: "0x1234" },
      addresses: [
        {
          coinType: COIN_TYPE_ETH,
          value: "0x51050ec063d393217B436747617aD1C2285Aeeee",
        },
      ],
    });

    resolve(
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
