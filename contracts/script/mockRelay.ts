import { type Hex, Log, parseEventLogs, TransactionReceipt } from "viem";
import type { CrossChainEnvironment, ChainDeployment } from "./setup.js";

function print(...a: unknown[]) {
  console.log("   -", ...a);
}

function pluralize(n: number) {
  return `${n} message${n == 1 ? "" : "s"}`;
}

function isShutdownError(error: unknown): boolean {
  if (!error || typeof error !== 'object') return false;
  const errorStr = error.toString();
  return (
    errorStr.includes('SocketClosedError') ||
    errorStr.includes('WebSocket connection') ||
    errorStr.includes('Failed to connect') ||
    errorStr.includes('socket has been closed') ||
    (error as any).code === 'ECONNREFUSED'
  );
}

async function waitForConnection(chain: ChainDeployment, maxAttempts = 5): Promise<void> {
  let attempt = 0;
  
  while (attempt < maxAttempts) {
    try {
      // Simple connection test by trying to get block number
      await chain.client.getBlockNumber();
      return; // Connection successful
    } catch (error) {
      attempt++;
      if (attempt >= maxAttempts) {
        throw new Error(`Failed to establish connection to ${chain.name} after ${maxAttempts} attempts`);
      }
      // Exponential backoff: 100ms, 200ms, 400ms, 800ms, 1600ms
      const delay = 100 * Math.pow(2, attempt - 1);
      await new Promise(resolve => setTimeout(resolve, delay));
    }
  }
}

export type MockRelay = Awaited<ReturnType<typeof setupMockRelay>>;

export type MockRelayReceipt =
  | TransactionReceipt
  | { status: "error"; error: unknown };


async function deliverSurgeMessage(chain: ChainDeployment, message: any, expected = false) {
  const errorPrefix = `deliverMessage() failed ${chain.arrow}:`;
  try {
    // Call deliverMessage on the destination chain's MockSurgeNativeBridge with the full message
    const hash = await chain.contracts.MockSurgeNativeBridge.write.deliverMessage([message]);
    print(`wait for ${chain.name} tx: ${hash}`);
    const receipt = await chain.client.waitForTransactionReceipt({ 
      hash, 
      timeout: 30000 // 30 second timeout
    });
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

export async function setupMockRelay(env: CrossChainEnvironment) {
  // Wait for connections to be ready before setting up event listeners
  await Promise.all([
    waitForConnection(env.l1),
    waitForConnection(env.l2)
  ]);

  const pending = new Map<Hex, (v: MockRelayReceipt[]) => void>();

  async function relay(chain: ChainDeployment, logs: Log[]) {
    const buckets = new Map<Hex, MockRelayReceipt[]>();
    // Use MockSurgeNativeBridge ABI for parsing events
    const surgeNativeBridgeAbi = chain.contracts.MockSurgeNativeBridge.abi;
    
    const parsedLogs = parseEventLogs({
      abi: surgeNativeBridgeAbi,
      logs,
    });
    
    for (const log of parsedLogs) {
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
          const message = log.args.message;
          bucket.push(await deliverSurgeMessage(chain.rx, message, pending.has(tx)));
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

  const unwatchL1 = env.l1.contracts.MockSurgeNativeBridge.watchEvent.MessageSent({}, {
    onLogs: (logs: Log[]) => {
      relay(env.l1, logs).catch(error => {
        // Only log if it's not a shutdown-related error
        if (!isShutdownError(error)) {
          console.error(`Error in L1 relay processing:`, error);
        }
      });
    },
    onError: (error) => {
      // Only log if it's not a shutdown-related error
      if (!isShutdownError(error)) {
        console.error(`L1 event watching error:`, error);
      }
    },
  });
  const unwatchL2 = env.l2.contracts.MockSurgeNativeBridge.watchEvent.MessageSent({}, {
    onLogs: (logs: Log[]) => {
      relay(env.l2, logs).catch(error => {
        // Only log if it's not a shutdown-related error
        if (!isShutdownError(error)) {
          console.error(`Error in L2 relay processing:`, error);
        }
      });
    },
    onError: (error) => {
      // Only log if it's not a shutdown-related error
      if (!isShutdownError(error)) {
        console.error(`L2 event watching error:`, error);
      }
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
      // Use MockSurgeNativeBridge ABI for parsing events
      const surgeBridgeAbi = chain.contracts.MockSurgeNativeBridge.abi;
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
