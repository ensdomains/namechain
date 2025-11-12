import { type Hex, Log, parseEventLogs, TransactionReceipt } from "viem";
import type { CrossChainEnvironment, ChainDeployment } from "./setup.js";

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
  const errorPrefix = `onMessageInvocation() failed ${chain.arrow}:`;
  try {
    // Get the appropriate bridge contract for the destination chain
    const bridgeContract = chain.isL1 ? (chain.contracts as any).L1Bridge : (chain.contracts as any).L2Bridge;
    
    // this will simulate the tx to estimate gas and fail if it reverts
    const hash = await bridgeContract.write.onMessageInvocation([message]);
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

async function deliverSurgeMessage(chain: ChainDeployment, msgHash: Hex, expected = false) {
  const errorPrefix = `deliverMessage() failed ${chain.arrow}:`;
  try {
    // Call deliverMessage on the destination chain's MockSurgeBridge
    const hash = await chain.contracts.MockSurgeBridge.write.deliverMessage([msgHash]);
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
    console.log(`Processing ${logs.length} logs from ${chain.name}`);
    const buckets = new Map<Hex, MockRelayReceipt[]>();
    // Use MockSurgeBridge ABI for parsing events
    const surgeBridgeAbi = chain.contracts.MockSurgeBridge.abi;
    
    const parsedLogs = parseEventLogs({
      abi: surgeBridgeAbi,
      logs,
    });
    console.log(`Parsed ${parsedLogs.length} events from MockSurgeBridge`);
    
    for (const log of parsedLogs) {
      console.log(`Event: ${log.eventName}, msgHash: ${log.args?.msgHash}`);
      // Only process MessageSent events
      if (log.eventName === 'MessageSent') {
        const tx = log.transactionHash;
        let bucket = buckets.get(tx);
        if (!bucket) {
          bucket = [];
          buckets.set(tx, bucket);
        }
        // process sequentially to avoid nonce issues
        try {
          console.log(`Delivering message to ${chain.rx.name} with msgHash: ${log.args.msgHash}`);
          bucket.push(await deliverSurgeMessage(chain.rx, log.args.msgHash, pending.has(tx)));
        } catch (error: unknown) {
          console.error(`Failed to deliver message: ${error}`);
          bucket.push({ status: "error", error });
        }
      }
    }
    // TODO: is this ever more than 1 thing?
    for (const [tx, bucket] of buckets) {
      pending.get(tx)?.(bucket);
    }
  }

  const unwatchL1 = env.l1.contracts.MockSurgeBridge.watchEvent.MessageSent({}, {
    onLogs: (logs: Log[]) => {
      console.log(`Mock relay received ${logs.length} MockSurgeBridge events from L1`);
      relay(env.l1, logs);
    },
  });
  const unwatchL2 = env.l2.contracts.MockSurgeBridge.watchEvent.MessageSent({}, {
    onLogs: (logs: Log[]) => {
      console.log(`Mock relay received ${logs.length} MockSurgeBridge events from L2`);
      relay(env.l2, logs);
    },
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
      // Use MockSurgeBridge ABI for parsing events  
      const surgeBridgeAbi = chain.contracts.MockSurgeBridge.abi;
      const sent = parseEventLogs({
        abi: surgeBridgeAbi,
        logs: receipt.logs,
      }).filter(log => log.eventName === 'MessageSent').length;
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
