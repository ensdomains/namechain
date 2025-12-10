import { type Hex, Log, parseEventLogs, TransactionReceipt } from "viem";
import type { ChainDeployment, CrossChainEnvironment } from "./setup.js";

function print(...a: unknown[]) {
  console.log("   -", ...a);
}

function pluralize(n: number) {
  return `${n} message${n == 1 ? "" : "s"}`;
}

export type MockRelay = ReturnType<typeof setupMockRelay>;

export type MockRelayReceipt =
  | TransactionReceipt
  | { status: "error"; error: unknown };

async function send(chain: ChainDeployment, message: Hex, expected = false) {
  const errorPrefix = `receiveMessage() failed ${chain.arrow}:`;
  try {
    // this will simulate the tx to estimate gas and fail if it reverts
    const hash = await chain.contracts.MockBridge.write.receiveMessage([
      message,
    ]);
    print(`wait for ${chain.name} tx: ${hash}`);
    const receipt = await chain.client.waitForTransactionReceipt({ hash });
    if (receipt.status !== "success") {
      throw Object.assign(new Error(errorPrefix), { receipt }); // rare
    }
    return receipt;
  } catch (err) {
    if (!expected) {
      console.error(errorPrefix, err);
    }
    throw err;
  }
}

export function setupMockRelay(env: CrossChainEnvironment) {
  const pending = new Map<Hex, (v: MockRelayReceipt[]) => void>();

  async function relay(chain: ChainDeployment, logs: Log[]) {
    const buckets = new Map<Hex, MockRelayReceipt[]>();
    for (const log of parseEventLogs({
      abi: chain.contracts.MockBridge.abi,
      logs,
    })) {
      const tx = log.transactionHash;
      let bucket = buckets.get(tx);
      if (!bucket) {
        bucket = [];
        buckets.set(tx, bucket);
      }
      // process sequentially to avoid nonce issues
      try {
        bucket.push(await send(chain.rx, log.args.message, pending.has(tx)));
      } catch (error: unknown) {
        bucket.push({ status: "error", error });
      }
    }
    // TODO: is this ever more than 1 thing?
    for (const [tx, bucket] of buckets) {
      pending.get(tx)?.(bucket);
    }
  }

  const unwatchL1 = env.l1.contracts.MockBridge.watchEvent.MessageSent({
    onLogs: (logs) => relay(env.l1, logs),
  });
  const unwatchL2 = env.l2.contracts.MockBridge.watchEvent.MessageSent({
    onLogs: (logs) => relay(env.l2, logs),
  });

  async function waitFor(tx: Promise<Hex>) {
    const hash = await tx;
    const { promise, resolve } = Promise.withResolvers<MockRelayReceipt[]>();
    try {
      pending.set(hash, resolve);
      const { receipt, chain } = await env.waitFor(hash);
      if (receipt.status !== "success") {
        throw Object.assign(new Error("waitFor() failed!"), { receipt }); // rare
      }
      const sent = parseEventLogs({
        abi: chain.contracts.MockBridge.abi,
        logs: receipt.logs,
      }).length;
      print(`sent ${chain.arrow}: ${pluralize(sent)}`);
      if (!sent) {
        resolve([]); // there were no messages
      }
      const rxReceipts = await promise;
      const success = rxReceipts.reduce(
        (a, x) => a + +(x.status === "success"),
        0,
      );
      print(`recv ${chain.arrow}: ${success}/${pluralize(sent)}`);
      return { txReceipt: receipt, rxReceipts };
    } finally {
      pending.delete(hash);
    }
  }
  console.log("Created Mock Relay");
  return {
    waitFor,
    removeListeners() {
      unwatchL1();
      unwatchL2();
    },
  };
}
