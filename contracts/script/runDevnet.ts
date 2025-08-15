import { type Address, toHex } from "viem";
import { createMockRelay } from "./mockRelay.js";
import { setupCrossChainEnvironment } from "./setup.js";

const env = await setupCrossChainEnvironment({
  l1Port: 8545,
  l2Port: 8456,
  urgPort: 8457,
});

let killed = false;
process.on("SIGINT", async () => {
  if (killed) return;
  killed = true;
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
console.log(
  Object.fromEntries(
    env.accounts.map((x, i) => [x.name || `unnamed${i}`, x.address]),
  ),
);

console.log("\nDeployments:");
console.log("============");
console.log({
  urg: (({ gateway, ...a }) => a)(env.urg),
  l1: dump(env.l1),
  l2: dump(env.l2),
});

function dump(deployment: typeof env.l1 | typeof env.l2) {
  const { client, hostPort, contracts, ...rest } = deployment;
  return {
    chain: toHex(client.chain.id),
    endpoint: `{http,ws}://${hostPort}`,
    contracts: extractAddresses(contracts),
    //...rest,
  };
}

function extractAddresses(obj: Record<string, { address: Address }>) {
  return Object.fromEntries(
    Object.entries(obj).map(([k, v]) => [k, v.address]),
  );
}
