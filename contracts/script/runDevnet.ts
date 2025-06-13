import { Address } from "viem";
import { setupCrossChainEnvironment } from "./setup.js";

const env = await setupCrossChainEnvironment();

process.on("SIGINT", async () => {
  console.log("\nShutting down...");
  await env.shutdown();
  process.exit();
});

console.log("\nAvailable Test Accounts:");
console.log("=======================");

const l2Accounts = (await env.l2.client.request({
  method: "eth_accounts",
})) as string[];

console.log("\nL1 and L2 Chain Test Accounts:");
l2Accounts.forEach((address: string, index: number) => {
  const privateKey = `0x${(BigInt("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80") + BigInt(index)).toString(16)}`;
  console.log(`Account ${index + 1}: ${address}`);
  console.log(`Private Key: ${privateKey}`);
  console.log("---");
});

console.log({
  urg: env.urg,
  l1: dump(env.l1),
  l2: dump(env.l2),
});

function dump(deployment: typeof env.l1 | typeof env.l2) {
  const { client, accounts, contracts, ...rest } = deployment;
  return {
    chain: client.chain.id,
    accounts: extractAddresses(accounts),
    contracts: extractAddresses(contracts),
    ...rest,
  };
}

function extractAddresses(obj: Record<string, { address: Address }>) {
  return Object.fromEntries(
    Object.entries(obj).map(([k, v]) => [k, v.address]),
  );
}
