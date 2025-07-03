import type { Client, Hash, Hex } from "viem";
import { waitForTransactionReceipt } from "viem/actions";
import { encodeAbiParameters, parseAbiParameters } from "viem";

import type { L1Client, L1Contracts, L2Client, L2Contracts } from "./setup.js";

const expectSuccess = async (client: Client, hashPromise: Promise<Hash>) => {
  const txHash = await hashPromise;
  const receipt = await waitForTransactionReceipt(client, { hash: txHash });
  if (receipt.status !== "success") throw new Error("Transaction failed!");
  return receipt;
};

export const createMockRelay = ({
  l1Bridge,
  l2Bridge,
  l1Client,
  l2Client,
}: {
  l1Bridge: L1Contracts["mockBridge"];
  l2Bridge: L2Contracts["mockBridge"];
  l1Client: L1Client;
  l2Client: L2Client;
}) => {
  console.log("Creating mock bridge...");

  // Listen for L1 bridge events (ejection/migration to L2)
  const unwatchL1Bridge = l1Bridge.watchEvent.NameBridgedToL2({
    onLogs: async (logs: any[]) => {
      for (const log of logs) {
        console.log("Relaying bridged message from L1 to L2");
        const { message } = log.args;
        try {
          const receipt = await expectSuccess(
            l2Client,
            (l2Bridge.write as any).receiveMessage([message])
          );
          console.log(`Message relayed to L2, tx hash: ${receipt.transactionHash}`);
        } catch (error) {
          console.error("Error relaying bridged message from L1 to L2:", error);
        }
      }
    },
  });

  // Listen for L2 bridge events (ejection to L1)
  const unwatchL2Bridge = l2Bridge.watchEvent.NameBridgedToL1({
    onLogs: async (logs: any[]) => {
      for (const log of logs) {
        console.log("Relaying bridged message from L2 to L1");
        const { message } = log.args;
        try {
          const receipt = await expectSuccess(
            l1Client,
            (l1Bridge.write as any).receiveMessage([message])
          );
          console.log(`Message relayed to L1, tx hash: ${receipt.transactionHash}`);
        } catch (error) {
          console.error("Error relaying bridged message from L2 to L1:", error);
        }
      }
    },
  });

  const manualRelay = async ({
    targetChain,
    message,
  }: {
    targetChain: "l1" | "l2";
    message: Hex;
  }) =>
    (targetChain === "l1"
      ? expectSuccess(l1Client, (l1Bridge.write as any).receiveMessage([message]))
      : expectSuccess(l2Client, (l2Bridge.write as any).receiveMessage([message]))
    )
      .then((receipt) => {
        console.log(
          `Message relayed to ${targetChain}, tx hash: ${receipt.transactionHash}`,
        );
        return receipt;
      })
      .catch((e) => {
        console.error(`Error in manual relay:`, e);
        throw e;
      });

  const removeListeners = () => {
    unwatchL1Bridge();
    unwatchL2Bridge();
  };

  return {
    manualRelay,
    removeListeners,
  };
};

export type MockRelay = ReturnType<typeof createMockRelay>;
