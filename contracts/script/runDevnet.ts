import { toHex } from "viem";
import { createMockRelay } from "./mockRelay.js";
import { setupCrossChainEnvironment } from "./setup.js";

const banner = `
███╗   ██╗ █████╗ ███╗   ███╗███████╗ ██████╗██╗  ██╗ █████╗ ██╗███╗   ██╗
████╗  ██║██╔══██╗████╗ ████║██╔════╝██╔════╝██║  ██║██╔══██╗██║████╗  ██║
██╔██╗ ██║███████║██╔████╔██║█████╗  ██║     ███████║███████║██║██╔██╗ ██║
██║╚██╗██║██╔══██║██║╚██╔╝██║██╔══╝  ██║     ██╔══██║██╔══██║██║██║╚██╗██║
██║ ╚████║██║  ██║██║ ╚═╝ ██║███████╗╚██████╗██║  ██║██║  ██║██║██║ ╚████║
╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝ ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝
`;

console.log(banner);
console.log("🚀 Starting NameChain Development Environment...\n");

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

console.log("\n📋 Available Test Accounts:");
console.log("============================");
console.table(env.accounts.map(({ name, address }, i) => ({ name, address })));

console.log("\n🏗️  Deployments:");
console.log("=================");

const urgDeployment = (({ gateway, ...a }) => a)(env.urg);
const l1Deployment = dump(env.l1);
const l2Deployment = dump(env.l2);

console.log("\n🔗 URG (Universal Resolver Gateway):");
console.table(Object.entries(urgDeployment).map(([key, value]) => ({ 
  Component: key, 
  Address: typeof value === 'string' ? value : JSON.stringify(value) 
})));

console.log("\n🌐 L1 (Layer 1):");
console.table(Object.entries(l1Deployment.contracts).map(([name, address]) => ({ 
  Contract: name, 
  Address: address 
})));

console.log("\n⚡ L2 (Layer 2):");
console.table(Object.entries(l2Deployment.contracts).map(([name, address]) => ({ 
  Contract: name, 
  Address: address 
})));

console.log("\n🔌 Endpoints:");
console.table([
  { Layer: "L1", Endpoint: l1Deployment.endpoint, ChainID: l1Deployment.chain },
  { Layer: "L2", Endpoint: l2Deployment.endpoint, ChainID: l2Deployment.chain }
]);

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
