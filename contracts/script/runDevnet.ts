import { getAddress, toHex } from "viem";
import { setupCrossChainEnvironment } from "./setup.js";
import {
  registerTestNames,
  showName,
  transferName,
  renewName,
  createSubname,
  bridgeName,
  changeRole,
  linkName,
} from "./testNames.js";
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
await registerTestNames(env, [
  "test",
  "example",
  "demo",
  "newowner",
  "renew",
  "parent",
  "bridge",
  "changerole",
]);

// Transfer newowner.eth to user
await transferName(env, "newowner.eth", env.namedAccounts.user.address);

// Renew renew.eth for 365 days
await renewName(env, "renew.eth", 365);

// Create subnames - need to create children too so sub1.sub2.parent.eth has a subregistry
const createdSubnames = await createSubname(env, "wallet.sub1.sub2.parent.eth");

// Change roles on changerole.eth - grant ROLE_SET_RESOLVER to user, revoke ROLE_SET_TOKEN_OBSERVER
await changeRole(
  env,
  "changerole.eth",
  env.namedAccounts.user.address,
  1n << 4n, // ROLE_SET_RESOLVER
  1n << 16n, // ROLE_SET_TOKEN_OBSERVER
);

// Link sub1.sub2.parent.eth to parent.eth with different label (creates linked.parent.eth with shared children)
// Now wallet.linked.parent.eth and wallet.sub1.sub2.parent.eth will be the same token
await linkName(env, "sub1.sub2.parent.eth", "parent.eth", "linked");

const allNames = [
  "test.eth",
  "example.eth",
  "demo.eth",
  "newowner.eth",
  "renew.eth",
  "parent.eth",
  "bridge.eth",
  "changerole.eth",
  ...createdSubnames,
  "linked.parent.eth",
  "wallet.linked.parent.eth", // Should also be same as wallet.sub1.sub2.parent.eth
];

// Bridge bridge.eth from L2 to L1
await bridgeName(env, "bridge.eth");

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
