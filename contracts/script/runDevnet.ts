import { toHex } from "viem";
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

console.log("\nAvailable Test Accounts:");
console.log("========================");
console.table(env.accounts.map(({ name, address }) => ({ name, address })));

console.log("\nDeployments:");
console.log("============");
console.log({
  urg: (({ gateway, ...a }) => a)(env.urg),
  l1: dump(env.l1),
  l2: dump(env.l2),
});

console.log(`\nReady! <${Date.now() - t0}ms>`);

function dump(deployment: typeof env.l1 | typeof env.l2) {
  const { client, hostPort, deployments } = deployment;
  return {
    chain: toHex(client.chain.id),
    endpoint: `{http,ws}://${hostPort}`,
    deployments,
  };
}
