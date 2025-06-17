import { createMockRelay } from "./mockRelay.js";
import { setupCrossChainEnvironment } from "./setup.js";

const env = await setupCrossChainEnvironment();

createMockRelay({
  l1Bridge: env.l1.contracts.mockBridge,
  l2Bridge: env.l2.contracts.mockBridge,
  l1Client: env.l1.client,
  l2Client: env.l2.client,
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

console.log("\nChain Info:");
console.log(`L1 Chain ID: ${env.l1.client.chain.id}`);
console.log(`L2 Chain ID: ${env.l2.client.chain.id}`);
console.log(`Other L2 Chain ID: ${env.otherL2.client.chain.id}`);
