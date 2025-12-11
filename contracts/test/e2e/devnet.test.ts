import { describe, expect, it } from "bun:test";
import { toHex } from "viem";
import { expectVar } from "../utils/expectVar.js";

describe("Devnet", () => {
  const env = process.env.TEST_GLOBALS!.env;
  const resetState = process.env.TEST_GLOBALS!.resetState;

  function blocks() {
    return Promise.all([env.l1.client, env.l2.client].map((x) => x.getBlock()));
  }

  it("sync", async () => {
    await env.l1.client.mine({ blocks: 1, interval: 10 }); // advance one chain
    let [a, b] = await blocks();
    expect(a.timestamp, "diff").not.toStrictEqual(b.timestamp); // check diff
    const t = await env.sync();
    [a, b] = await blocks();
    expect(b.timestamp, "after").toStrictEqual(a.timestamp); // check same
    expectVar({ t }).toStrictEqual(a.timestamp); // check estimate
  });

  it("warp", async () => {
    const warpSec = 60;
    let [a0, b0] = await blocks();
    const t = await env.sync({ warpSec }); // time warp
    let [a1, b1] = await blocks();
    expect(a1.timestamp - a0.timestamp, "diff1").toBeGreaterThanOrEqual(
      warpSec,
    );
    expect(b1.timestamp - b0.timestamp, "diff2").toBeGreaterThanOrEqual(
      warpSec,
    );
    expect(a1.timestamp, "1").toBeGreaterThanOrEqual(t);
    expect(b1.timestamp, "2").toBeGreaterThanOrEqual(t);
    expectVar({ t }).toBeGreaterThanOrEqual(Math.floor(Date.now() / 1000));
  });

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

  it(`computeVerifiableProxyAddress`, async () => {
    for (const lx of [env.l1, env.l2]) {
      const account = env.namedAccounts.deployer;
      const salt = 1234n;
      const contract = await lx.deployDedicatedResolver({ account, salt });
      const address = await lx.computeVerifiableProxyAddress({
        deployer: account.address,
        salt,
      });
      expect(address, lx.name).toStrictEqual(contract.address);
    }
  });
});
