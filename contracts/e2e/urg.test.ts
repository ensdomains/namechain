import { describe, it, beforeAll, afterAll } from "vitest";
import { zeroAddress } from "viem";

import { type CrossChainEnvironment, setupCrossChainEnvironment } from "../script/setup.js";
import { dnsEncodeName } from "../test/utils/utils.js";
import {
  COIN_TYPE_ETH,
  COIN_TYPE_DEFAULT,
  type KnownProfile,
  makeResolutions,
  bundleCalls,
} from "../test/utils/resolutions.js";

describe("Urg", () => {
  let env: CrossChainEnvironment;
  beforeAll(async () => {
    env = await setupCrossChainEnvironment();
    afterAll(env.shutdown);
  });

  let count = 0;
  function resolve(set: Omit<KnownProfile, "name">, get = set) {
    const label = `test${count++}`;
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
        BigInt(Math.floor(Date.now() / 1000) + 10000),
      ]);

      await env.sync();
      const bundle = bundleCalls(gets);
      const [answer] = await env.l1.contracts.UniversalResolver.read.resolve([
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
