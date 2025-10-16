import { getAddress, toHex } from "viem";
import { setupCrossChainEnvironment } from "./setup.js";
import { registerTestNames, showName, transferName, renewName, createSubname, bridgeName } from "./testNames.js";
import { setupMockRelay } from "./mockRelay.js";
import { createServer } from "node:http";
import { parseArgs } from "node:util";

const t0 = Date.now();

const args = parseArgs({
  args: process.argv.slice(2),
  options: {
    procLog: {
      type: "boolean",
    },
  },
});

const env = await setupCrossChainEnvironment({
  l1Port: 8545,
  l2Port: 8546,
  urgPort: 8547,
  saveDeployments: true,
  procLog: args.values.procLog,
});

// handler for shell
process.once("SIGINT", async () => {
  console.log("\nShutting down...");
  await env.shutdown();
  process.exit();
});
// handler for docker
process.once("SIGTERM", async (code) => {
  await env.shutdown();
  process.exit(0);
});
// handler for bugs
process.once("uncaughtException", async (err) => {
  await env.shutdown();
  throw err;
});

const relay = setupMockRelay(env);

console.log();
console.log("Available Named Accounts:");
console.table(env.accounts.map((x) => ({ Name: x.name, Address: x.address })));

console.table(
  Object.fromEntries(
    [env.l1, env.l2].map((x) => [
      x.client.chain.name,
      {
        Chain: `${x.client.chain.id} (${toHex(x.client.chain.id)})`,
        Endpoint: `{http,ws}://${x.hostPort}`,
      },
    ]),
  ),
);
console.log("Unruggable Gateway:", (({ gateway, ...a }) => a)(env.urg));

for (const lx of [env.l1, env.l2]) {
  console.table(
    Object.entries(lx.env.deployments).map(([name, { address }]) => ({
      [lx.client.chain.name]: name,
      "Contract Address": getAddress(address),
    })),
  );
}

// Register all test names with default 1 year expiry
await registerTestNames(env, ["test", "example", "demo", "newowner", "renew", "parent"]);

// Transfer newowner.eth to user
await transferName(env, "newowner.eth", env.namedAccounts.user.address);

// Renew renew.eth for 365 days
await renewName(env, "renew.eth", 365);

// Bridge bridge.eth from L2 to L1
// NOTE: Bridging works in E2E tests but fails in devnet with ERC1155InvalidReceiver error
// The issue is environment-specific - all contracts are correctly deployed and configured
// Use `bun test test/e2e/bridge.test.ts` to verify bridging functionality
// TODO: Investigate why devnet environment behaves differently from E2E test environment
// await bridgeName(env, relay, "bridge.eth");

// Create subnames
const createdSubnames = await createSubname(env, "sub1.sub2.parent.eth");

const allNames = [
  "test.eth",
  "example.eth",
  "demo.eth",
  "newowner.eth",
  "renew.eth",
  "parent.eth",
  ...createdSubnames,
];

await showName(env, allNames);

console.log(new Date(), `Ready! <${Date.now() - t0}ms>`);

const server = createServer((_req, res) => {
  res.writeHead(200, { "Content-Type": "text/plain" });
  res.end("healthy\n");
});

server.listen(8000, () => {
  console.log(`Healthcheck endpoint listening on :8000/health`);
});

// ensure server shuts down with the env
process.once("exit", () => server.close());
