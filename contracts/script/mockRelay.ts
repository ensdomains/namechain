import { Log, parseEventLogs, TransactionReceipt, type Hex } from "viem";
import type { CrossChainEnvironment, ChainDeployment } from "./setup.js";

function print(...a: any[]) {
  console.log("   ->", ...a);
}

export type MockRelay = ReturnType<typeof setupMockRelay>;

export type MockRelayReceipt = PromiseSettledResult<TransactionReceipt>;

async function send(chain: ChainDeployment, message: Hex, waiting = false) {
  const errorPrefix = `receiveMessage failed[${chain.name}->${chain.rx.name}]:`;
  try {
    const hash = await chain.contracts.MockBridge.write.receiveMessage([
      message,
    ]);
    print(`waiting for tx: ${hash} [${chain.name}]`);
    const receipt = await chain.client.waitForTransactionReceipt({ hash });
    if (receipt.status !== "success") {
      throw new Error(`${errorPrefix} ${receipt.status}`);
    }
    return receipt;
  } catch (err) {
    if (!waiting) {
      console.error(errorPrefix, err);
    }
    throw err;
  }
}

export function setupMockRelay(env: CrossChainEnvironment) {
  const pending = new Map<Hex, (v: MockRelayReceipt[]) => void>();

  async function relay(chain: ChainDeployment, logs: Log[]) {
    const buckets = new Map<Hex, Promise<TransactionReceipt>[]>();
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
      bucket.push(send(chain.rx, log.args.message, pending.has(tx)));
    }
    // TODO: is this ever more than 1 thing?
    for (const [tx, bucket] of buckets) {
      const answer = await Promise.allSettled(bucket);
      pending.get(tx)?.(answer);
    }
  }

  const unwatchL1 = env.l1.contracts.MockBridge.watchEvent.MessageSent({
    onLogs: (logs) => relay(env.l1, logs),
  });
  const unwatchL2 = env.l2.contracts.MockBridge.watchEvent.MessageSent({
    onLogs: (logs) => relay(env.l2, logs),
  });

  async function waitFor(tx: Promise<Hex>, timeoutMs = 1000) {
    let hash = await tx;
    const { promise, resolve, reject } =
      Promise.withResolvers<MockRelayReceipt[]>();
    const timer = setTimeout(() => reject(new Error("Timeout")), timeoutMs);
    try {
      pending.set(hash, resolve);
      print(`waiting for tx: ${hash}`);
      const txReceipt = await Promise.any([
        env.l1.client.waitForTransactionReceipt({ hash }),
        env.l2.client.waitForTransactionReceipt({ hash }),
      ]);
      if (txReceipt.status !== "success") {
        console.error(txReceipt);
        throw new Error("waitFor() failed!");
      }
      const rxReceipts = await promise;
      const success = rxReceipts.reduce(
        (a, x) => a + +(x.status === "fulfilled"),
        0,
      );
      print(`relayed ${success}/${rxReceipts.length} messages!`);
      return { txReceipt, rxReceipts };
    } finally {
      clearTimeout(timer);
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
