import { createServer } from "node:http";
import { parseArgs } from "node:util";
import { getAddress, toHex } from "viem";
import { setupMockRelay } from "./mockRelay.js";
import { setupCrossChainEnvironment } from "./setup.js";
import { testNames } from "./testNames.js";

const t0 = Date.now();

const args = parseArgs({
  args: process.argv.slice(2),
  options: {
    procLog: {
      type: "boolean",
    },
    testNames: {
      type: "boolean",
    },
  },
});

const env = await setupCrossChainEnvironment({
  l1Port: 48545,
  l2Port: 48546,
  urgPort: 48547,
  saveDeployments: true,
  procLog: args.values.procLog,
  extraTime: args.values.testNames ? 86_401 : 0,
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

setupMockRelay(env);

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

if (args.values.testNames) {
  await testNames(env);
}

let [l1Timestamp, l2Timestamp, actualTimestamp] = await Promise.all([
  env.l1.client.getBlock().then((b) => b.timestamp),
  env.l2.client.getBlock().then((b) => b.timestamp),
  BigInt(Math.floor(Date.now() / 1000)),
]);

if (l1Timestamp !== l2Timestamp) {
  console.log(new Date(), "Syncing timestamps at launch...");
  // sync timestamps at launch
  l1Timestamp = await env.sync({ warpSec: 0 });
}

const actualTimestampMismatch = Number(actualTimestamp - l1Timestamp);

if (actualTimestampMismatch !== 0) {
  if (actualTimestampMismatch > 0) {
    console.log(new Date(), "Syncing timestamps to catch up to local time...");
    // chain timestamps are in the past, can be corrected
    await env.sync({ warpSec: actualTimestampMismatch });
  } else {
    const formatTs = (timestamp: bigint) =>
      new Date(Number(timestamp) * 1000).toISOString();
    // chain timestamps are in the future, cannot be corrected
    console.warn(
      new Date(),
      "WARN",
      `Chain timestamps are in the future, cannot be corrected: <${formatTs(l1Timestamp)}> !== <${formatTs(actualTimestamp)}>; difference: <${actualTimestampMismatch}s>`,
    );
  }
}

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
