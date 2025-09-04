import { getAddress, toHex } from "viem";
import { createMockRelay } from "./mockRelay.js";
import { setupCrossChainEnvironment } from "./setup.js";

const t0 = Date.now();

const env = await setupCrossChainEnvironment({
  l1Port: 8545,
  l2Port: 8456,
  urgPort: 8457,
  saveDeployments: true,
});

process.once("SIGINT", async () => {
  console.log("\nShutting down...");
  await env.shutdown();
  process.exit();
});

createMockRelay(env);

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
    Object.entries(lx.deployments).map(([name, address]) => ({
      [lx.client.chain.name]: name,
      "Contract Address": getAddress(address),
    })),
  );
}

console.log();
console.log(new Date(), `Ready! <${Date.now() - t0}ms>`);

function printSection(name: string) {
  console.log();
  console.log(name);
  console.log("=".repeat(name.length));
}
