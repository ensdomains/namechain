import { beforeAll, describe, expect, it } from "bun:test";
import { toHex } from "viem";
import { expectVar } from "../utils/expectVar.js";

describe("Devnet", () => {
  const { env, setupEnv, resetInitialState } = process.env.TEST_GLOBALS!;

  setupEnv({ resetOnEach: true });

  it("sync", async () => {
    await env.l1.client.mine({ blocks: 1, interval: 10 }); // advance one chain
    const [a0, b0] = await env.getBlocks();
    expect(a0.timestamp, "diff").not.toStrictEqual(b0.timestamp); // check diff
    const t = await env.sync();
    const [a1, b1] = await env.getBlocks();
    expect(b1.timestamp, "after").toStrictEqual(a1.timestamp); // check same
    expectVar({ t }).toStrictEqual(a1.timestamp); // check estimate
  });

  it("warp", async () => {
    const warpSec = 60;
    const [a0, b0] = await env.getBlocks();
    const t = await env.sync({ warpSec }); // time warp
    const [a1, b1] = await env.getBlocks();
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

  it("saveState", async () => {
    const gateways =
      await env.l1.contracts.BatchGatewayProvider.read.gateways();
    await env.l1.contracts.BatchGatewayProvider.write.setGateways([[]], {
      account: env.namedAccounts.owner,
    });
    expect(
      env.l1.contracts.BatchGatewayProvider.read.gateways(),
    ).resolves.toStrictEqual([]);
    await resetInitialState();
    expect(
      env.l1.contracts.BatchGatewayProvider.read.gateways(),
    ).resolves.toStrictEqual(gateways);
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
