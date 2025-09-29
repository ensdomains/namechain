import { getAddress, toHex } from "viem";
import { setupCrossChainEnvironment } from "./setup.js";
import { registerTestNames } from "./testNames.js";
import { setupMockRelay } from "./mockRelay.ts";

const t0 = Date.now();

const env = await setupCrossChainEnvironment({
  l1Port: 8545,
  l2Port: 8546,
  urgPort: 8547,
  saveDeployments: true,
});

// handler for shell
process.once("SIGINT", async () => {
  console.log("\nShutting down...");
  await env.shutdown();
  process.exit();
});
// handler for docker
process.once("SIGTERM", async (code) => {
  await env.shutdown();
  process.exit(code);
});
// handler for bugs
process.once("uncaughtException", async (err) => {
  await env.shutdown();
  throw err;
});

setupMockRelay(env);

console.log();
console.log("Available Named Accounts:");
console.table(env.accounts.map((x) => ({ Name: x.name, Address: x.address })));

console.table(
  Object.fromEntries(
    [env.l1, env.l2].map((x) => [
      x.client.chain.name,
      {
        Chain: `${x.client.chain.id} (${toHex(x.client.chain.id)})`,
        Endpoint: `{http,ws}://${x.hostPort}`,
      },
    ]),
  ),
);
console.log("Unruggable Gateway:", (({ gateway, ...a }) => a)(env.urg));

for (const lx of [env.l1, env.l2]) {
  console.table(
    Object.entries(lx.env.deployments).map(([name, { address }]) => ({
      [lx.client.chain.name]: name,
      "Contract Address": getAddress(address),
    })),
  );
}

await registerTestNames(env, ["test", "example", "demo"]);

console.log();
console.log(new Date(), `Ready! <${Date.now() - t0}ms>`);
