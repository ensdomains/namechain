import type { Client, Hash, Hex } from "viem";
import { waitForTransactionReceipt } from "viem/actions";

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

  const unwatchL1 = l1Bridge.watchEvent.L1ToL2Message({
    onLogs: async (logs) => {
      for (const log of logs) {
        const message = log.args.message!;
        console.log("Relaying message from L1 to L2");
        console.log(`Message: ${message}`);
        console.log(`Transaction: ${log.transactionHash}`);

        await expectSuccess(
          l2Client,
          l2Bridge.write.receiveMessageFromL1([message]),
        ).catch((e) => {
          console.error(`Error relaying message to L2:`, e);
        });
      }
    },
  });

  const unwatchL2 = l2Bridge.watchEvent.L2ToL1Message({
    onLogs: async (logs) => {
      for (const log of logs) {
        const message = log.args.message!;
        console.log("Relaying message from L2 to L1");
        console.log(`Message: ${message}`);
        console.log(`Transaction: ${log.transactionHash}`);

        await expectSuccess(
          l1Client,
          l1Bridge.write.receiveMessageFromL2([message]),
        ).catch((e) => {
          console.error(`Error relaying message to L1:`, e);
        });
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
      ? expectSuccess(l1Client, l1Bridge.write.receiveMessageFromL2([message]))
      : expectSuccess(l2Client, l2Bridge.write.receiveMessageFromL1([message]))
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
    unwatchL1();
    unwatchL2();
  };

  return {
    manualRelay,
    removeListeners,
  };
};

export type MockRelay = ReturnType<typeof createMockRelay>;
