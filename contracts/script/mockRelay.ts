import type { Hex } from "viem";
import type { CrossChainEnvironment } from "./setup.js";

export function createMockRelay(env: CrossChainEnvironment) {
  const { bridger } = env.namedAccounts;
  const bridge1 = env.l1.contracts.mockBridge;
  const bridge2 = env.l2.contracts.mockBridge;
  const pending = new Map<
    Hex,
    {
      resolve: () => void;
      reject: (reason?: any) => void;
    }
  >();

  async function sendToL2(message: Hex) {
    console.log("Relaying bridged message from L1 to L2");
    try {
      const hash = await bridge2.write.receiveMessage([message]);
      const receipt = await env.l2.client.waitForTransactionReceipt({ hash });
      if (receipt.status !== "success") throw new Error("Transaction failed!");
      console.log(`Message relayed to L2, tx hash: ${hash}`);
      return receipt;
    } catch (err) {
      console.error("Error relaying bridged message from L1 to L2:", err);
      throw err;
    }
  }

  async function sendToL1(message: Hex) {
    console.log("Relaying bridged message from L2 to L1");
    try {
      const hash = await bridge1.write.receiveMessage([message], {
        account: bridger,
      });
      const receipt = await env.l1.client.waitForTransactionReceipt({ hash });
      if (receipt.status !== "success") throw new Error("Transaction failed!");
      console.log(`Message relayed to L1, tx hash: ${hash}`);
      return receipt;
    } catch (err) {
      console.error("Error relaying bridged message from L2 to L1:", err);
      throw err;
    }
  }

  const unwatchL1 = bridge1.watchEvent.NameBridgedToL2({
    onLogs: async (logs) => {
      for (const log of logs) {
        const { message } = log.args;
        if (!message) continue;
        console.log(`   -> received event from mock bridge on L1: ${log.transactionHash}`);
        const waiter = pending.get(log.transactionHash);
        try {
          console.log(`   -> relaying tx to L2`);
          await sendToL2(message);
          waiter?.resolve();
        } catch (err: any) {
          console.log(`   -> relay tx failed :/`);
          waiter?.reject(err);
        }
      }
    },
  });

  const unwatchL2 = bridge2.watchEvent.NameBridgedToL1({
    onLogs: async (logs) => {
      for (const log of logs) {
        const { message } = log.args;
        if (!message) continue;
        console.log(`   -> received event from mock bridge on L2: ${log.transactionHash}`);
        const waiter = pending.get(log.transactionHash);
        try {
          console.log(`   -> relaying tx to L1`);
          await sendToL1(message);
          waiter?.resolve();
        } catch (err: any) {
          console.log(`   -> relay tx failed :/`);
          waiter?.reject(err);
        }
      }
    },
  });

  async function waitFor(tx: Promise<Hex>) {
    let hash
    try {
      hash = await tx;
    } catch (err) {
      console.log(`   -> tx failed :/`);
      throw err;
    }

    console.log(`   -> tx hash: ${hash}`);

    const { promise, resolve, reject } = Promise.withResolvers<void>();
    
    try {
      pending.set(hash, { resolve, reject });
      console.log(`   -> waiting for tx`);
      const receipt = await Promise.any([
        env.l1.client.waitForTransactionReceipt({ hash }),
        env.l2.client.waitForTransactionReceipt({ hash }),
      ]);
      if (receipt.status !== "success") {
        console.error(receipt)
        throw new Error(`Transaction failed!`);
      }
      return promise.then(() => {
        console.log(`   -> relay tx success!`);
        return receipt;
      });
    } catch (err) {
      console.log(`   -> tx failed :/`);
      throw err;
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

export type MockRelayer = ReturnType<typeof createMockRelay>;
