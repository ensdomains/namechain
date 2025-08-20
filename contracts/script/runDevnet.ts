import { toHex } from "viem";
import { createMockRelay } from "./mockRelay.js";
import { setupCrossChainEnvironment, type ChainDeployment } from "./setup.js";

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
console.table(env.accounts.map(({ name, address }, i) => ({ name, address })));

console.log("\nDeployments:");
console.log("============");
console.log({
  urg: (({ gateway, ...a }) => a)(env.urg),
  l1: dump(env.l1),
  l2: dump(env.l2),
});

function dump(deployment: ChainDeployment) {
  const { client, hostPort, contracts } = deployment;
  return {
    chain: toHex(client.chain.id),
    endpoint: `{http,ws}://${hostPort}`,
    contracts: Object.fromEntries(
      Object.entries(contracts).map(([k, v]) => [k, v.address]),
    ),
  };
}
