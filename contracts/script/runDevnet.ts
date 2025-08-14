import {
  zeroHash,
  zeroAddress,
  type Address,
  encodeFunctionData,
  decodeFunctionResult,
} from "viem";
import { createMockRelay } from "./mockRelay.js";
import { setupCrossChainEnvironment } from "./setup.js";
import { dnsEncodeName } from "../test/utils/utils.ts";
import { artifacts } from "@rocketh";

const env = await setupCrossChainEnvironment();

process.on("SIGINT", async () => {
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
console.log(Object.fromEntries(env.accounts.map((x, i) => [i + 1, x.address])));

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
    chain: client.chain.id,
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
