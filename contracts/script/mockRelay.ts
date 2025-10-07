import type { Hex } from "viem";
import type { CrossChainEnvironment } from "./setup.js";

function print(...a: any[]) {
  console.log("   ->", ...a);
}

export type MockRelay = ReturnType<typeof setupMockRelay>;

export function setupMockRelay(env: CrossChainEnvironment) {
  const pending = new Map<
    Hex,
    {
      resolve: () => void;
      reject: (reason?: any) => void;
    }
  >();

  async function sendToL1(message: Hex) {
    try {
      const hash = await env.l1.contracts.MockBridge.write.receiveMessage([
        message,
      ]);
      print(`waiting for tx: ${hash} [L1]`);
      const receipt = await env.l1.client.waitForTransactionReceipt({ hash });
      if (receipt.status !== "success") throw new Error("Transaction failed!");
      return receipt;
    } catch (err) {
      console.error("Error relaying bridged message from L2 to L1:", err);
      throw err;
    }
  }

  async function sendToL2(message: Hex) {
    try {
      const hash = await env.l2.contracts.MockBridge.write.receiveMessage([
        message,
      ]);
      print(`waiting for tx: ${hash} [L2]`);
      const receipt = await env.l2.client.waitForTransactionReceipt({ hash });
      if (receipt.status !== "success") throw new Error("Transaction failed!");
      return receipt;
    } catch (err) {
      console.error("Error relaying bridged message from L1 to L2:", err);
      throw err;
    }
  }

  const unwatchL1 = env.l1.contracts.MockBridge.watchEvent.MessageSent({
    onLogs: async (logs) => {
      for (const log of logs) {
        const { message } = log.args;
        if (!message) continue;
        const waiter = pending.get(log.transactionHash);
        try {
          await sendToL2(message);
          waiter?.resolve();
        } catch (err: any) {
          waiter?.reject(err);
        }
      }
    },
  });

  const unwatchL2 = env.l2.contracts.MockBridge.watchEvent.MessageSent({
    onLogs: async (logs) => {
      for (const log of logs) {
        const { message } = log.args;
        if (!message) continue;
        const waiter = pending.get(log.transactionHash);
        try {
          await sendToL1(message);
          waiter?.resolve();
        } catch (err: any) {
          waiter?.reject(err);
        }
      }
    },
  });

  async function waitFor(tx: Promise<Hex>) {
    let hash = await tx;
    const { promise, resolve, reject } = Promise.withResolvers<void>();
    try {
      pending.set(hash, { resolve, reject });
      print(`waiting for tx: ${hash}`);
      const receipt = await Promise.any([
        env.l1.client.waitForTransactionReceipt({ hash }),
        env.l2.client.waitForTransactionReceipt({ hash }),
      ]);
      if (receipt.status !== "success") {
        console.error(receipt);
        throw new Error(`Transaction failed!`);
      }
      await promise;
      print(`relay success!`);
      return receipt;
    } finally {
      pending.delete(hash);
    }
  }

  console.log("Created Mock Relay");
  return {
    waitFor,
    sendToL1,
    sendToL2,
    removeListeners() {
      unwatchL1();
      unwatchL2();
    },
  };
}
