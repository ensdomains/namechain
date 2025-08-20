import { toHex, labelhash, zeroAddress } from "viem";
import { createMockRelay } from "./mockRelay.js";
import { setupCrossChainEnvironment } from "./setup.js";

const env = await setupCrossChainEnvironment({
  l1Port: 8545,
  l2Port: 8456,
  urgPort: 8457,
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

// Register default test names on L2
async function registerTestNames() {
  console.log("\n📝 Registering default test names on L2...");

  const testNames = ["test", "example", "demo"];
  const owner = env.accounts[1]; // Use second account as owner

  for (const label of testNames) {
    try {
      // Deploy a dedicated resolver for this name (same as test)
      const resolver = await env.l2.deployDedicatedResolver(owner);

      // Register the name exactly like in urg.test.ts
      await env.l2.contracts.ethRegistry.write.register([
        label,
        owner.address,
        zeroAddress,
        resolver.address,
        0n,
        BigInt(Math.floor(Date.now() / 1000) + 10000),
      ]);

      // Set some default records
      await resolver.write.setAddr(
        [
          60n, // ETH coin type
          owner.address,
        ],
        { account: owner },
      );

      await resolver.write.setText(
        ["description", `Default test name: ${label}.eth`],
        { account: owner },
      );

      console.log(`   ✅ Registered ${label}.eth`);
      console.log(`      Owner: ${owner.address}`);
      console.log(`      Resolver: ${resolver.address}`);
    } catch (error) {
      console.log(`   ⚠️  Failed to register ${label}.eth: ${error.message}`);
    }
  }

  console.log("\n📋 Test names registered:");
  console.log("   - test.eth");
  console.log("   - example.eth");
  console.log("   - demo.eth");
}

// Register test names
await registerTestNames();

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
