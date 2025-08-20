import { toHex } from "viem";
import { setupCrossChainEnvironment } from "./setup.js";
import { createMockRelay } from "./mockRelay.js";
import { registerTestNames } from "./testNames.js";

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

createMockRelay({
  l1Bridge: env.l1.contracts.mockBridge,
  l2Bridge: env.l2.contracts.mockBridge,
  l1Client: env.l1.client,
  l2Client: env.l2.client,
});

console.log("\nAvailable Test Accounts:");
console.log("========================");
console.table(env.accounts.map(({ name, address }) => ({ name, address })));

function dump(deployment: typeof env.l1 | typeof env.l2) {
  const { client, hostPort, contracts } = deployment;
  return {
    chain: toHex(client.chain.id),
    endpoint: `{http,ws}://${hostPort}`,
    contracts: Object.fromEntries(
      Object.entries(contracts).map(([k, v]) => [k, v.address]),
    ),
  };
}

console.log("\nDeployments:");
console.log("============");
console.log({
  urg: (({ gateway, ...a }) => a)(env.urg),
  l1: dump(env.l1),
  l2: dump(env.l2),
});

await registerTestNames(env, ["test", "example", "demo"]);

console.log("\nReady!");
