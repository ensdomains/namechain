import { labelhash, type Client, type Hash } from "viem";
import { waitForTransactionReceipt } from "viem/actions";

export const expectTransactionSuccess = async (
  client: Client,
  hashPromise: Promise<Hash>,
) => {
  const txHash = await hashPromise;
  const receipt = await waitForTransactionReceipt(client, { hash: txHash });
  if (receipt.status !== "success") throw new Error("Transaction failed!");
  return receipt;
};

export const labelToCanonicalId = (label: string) => {
  const id = BigInt(labelhash(label));

  return getCanonicalId(id);
};

export const getCanonicalId = (id: bigint) => {
  const idBigInt = BigInt(id);
  const mask = BigInt(
    "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000",
  );

  return idBigInt & mask;
};

export const waitForEvent = async <
  func extends (args: { onLogs: (logs: unknown) => unknown }) => () => void,
>(
  eventWatchFunction: func,
  timeout = 3_000,
): Promise<Parameters<Parameters<func>[0]["onLogs"]>[0]> =>
  Promise.race([
    new Promise((resolve) => {
      const unwatch = eventWatchFunction({
        onLogs: (logs) => {
          unwatch();
          resolve(logs);
        },
      });
    }),
    new Promise((_, reject) => {
      setTimeout(() => reject(new Error("Timeout waiting for event")), timeout);
    }),
  ]);
