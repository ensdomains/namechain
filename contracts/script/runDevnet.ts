// import { setupCrossChainEnvironment, CrossChainRelayer } from './setup.js';

// setupCrossChainEnvironment()
//   .then((env) => {
//     // Create a relayer
//     const relayer = new CrossChainRelayer(
//       env.l1.bridge,
//       env.l2.bridge,
//       env.L1,
//       env.L2
//     );

//     console.log('Setup complete! Cross-chain relayer is running.');
//     console.log('Keep this process running to relay cross-chain messages.');

//     // Export environment for interactive use
//     global.env = env;
//     global.relayer = relayer;
//     console.log(
//       'Environment and relayer exported to global variables for interactive use'
//     );
//     console.log(`L1: ${env.L1.endpoint} Chain ID: ${env.L1.chain}`);
//     console.log(`L2: ${env.L2.endpoint} Chain ID: ${env.L2.chain}`);
//   })
//   .catch((error) => {
//     console.error('Error setting up environment:', error);
//     process.exit(1);
//   });

import { setupCrossChainEnvironment } from "./setup.js";

const env = await setupCrossChainEnvironment();

console.log("\nAvailable Test Accounts:");
console.log("=======================");

const l2Accounts = await env.l2.client.request({
  method: "eth_accounts",
}) as string[];

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
