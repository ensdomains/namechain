import { artifacts, execute } from "@rocketh";
import {
  encodeFunctionData,
  TransactionReceiptNotFoundError,
  UserRejectedRequestError,
  zeroAddress,
} from "viem";
import { dnsEncodeName } from "../../test/utils/utils.js";
import { MAX_EXPIRY } from "../constants.js";

async function fetchPublicSuffixes() {
  const res = await fetch(
    "https://publicsuffix.org/list/public_suffix_list.dat",
    { headers: { Connection: "close" } },
  );
  if (!res.ok) throw new Error(`expected suffixes: ${res.status}`);
  return (await res.text())
    .split("\n")
    .map((x) => x.trim())
    .filter((x) => x && !x.startsWith("//"));
}

export default execute(
  async ({
    deploy,
    execute: write,
    get,
    getV1,
    tx,
    namedAccounts: { deployer },
    addressSigners,
    network,
    viem,
  }) => {
    const ensRegistryV1 =
      getV1<(typeof artifacts.ENSRegistry)["abi"]>("ENSRegistry");

    const dnsTLDResolverV1 = getV1<
      (typeof artifacts.OffchainDNSResolver)["abi"]
    >("OffchainDNSResolver");

    const publicSuffixList = getV1<
      (typeof artifacts.SimplePublicSuffixList)["abi"]
    >("SimplePublicSuffixList");

    const rootRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("RootRegistry");

    const dnssecOracle = getV1<(typeof artifacts.DNSSEC)["abi"]>("DNSSECImpl");

    const batchGatewayProvider = getV1<
      (typeof artifacts.GatewayProvider)["abi"]
    >("BatchGatewayProvider");

    const dnssecGatewayProvider = get<
      (typeof artifacts.GatewayProvider)["abi"]
    >("DNSSECGatewayProvider");

    const dnsTLDResolver = await deploy("DNSTLDResolver", {
      account: deployer,
      artifact: artifacts.DNSTLDResolver,
      args: [
        ensRegistryV1.address,
        dnsTLDResolverV1.address,
        rootRegistry.address,
        dnssecOracle.address,
        dnssecGatewayProvider.address,
        batchGatewayProvider.address,
      ],
    });

    let suffixes = await fetchPublicSuffixes();
    suffixes = await viem.publicClient
      .multicall({
        contracts: suffixes.map((suffix) => ({
          address: publicSuffixList.address,
          abi: publicSuffixList.abi,
          functionName: "isPublicSuffix",
          args: [dnsEncodeName(suffix)],
        })),
      })
      .then((results) =>
        results
          .map((result, i) => (result.result ? suffixes[i] : ""))
          .filter(Boolean),
      );

    suffixes = await viem.publicClient
      .multicall({
        contracts: suffixes.map((suffix) => ({
          address: rootRegistry.address,
          abi: rootRegistry.abi,
          functionName: "getNameData",
          args: [suffix],
        })),
      })
      .then((results) =>
        results
          .map((result, i) =>
            !result.result || result.result[1].expiry < Date.now() / 1000
              ? suffixes[i]
              : "",
          )
          .filter(Boolean),
      );

    console.log("suffixes", suffixes);

    const chunks = [];
    for (let i = 0; i < suffixes.length; i += 25) {
      chunks.push(suffixes.slice(i, i + 25));
    }
    for (let i = 0; i < chunks.length; i++) {
      const chunk = chunks[i];
      console.log(
        `Sending chunk ${i + 1} of ${chunks.length} (${chunk.length} transactions)`,
      );

      const nonce = await viem.publicClient.getTransactionCount({
        address: deployer,
      });
      const fees = await viem.publicClient.estimateFeesPerGas({
        chain: network.chain,
      });

      console.log("signing chunk");
      const signedTransactions = await Promise.all(
        chunk.map(async (suffix, i) =>
          viem.walletClient.signTransaction({
            account: addressSigners[deployer].signer.account,
            to: rootRegistry.address,
            nonce: nonce + i,
            data: encodeFunctionData({
              abi: rootRegistry.abi,
              functionName: "register",
              args: [
                suffix,
                deployer, // TODO: ownership
                zeroAddress,
                dnsTLDResolver.address,
                0n, // TODO: roles
                MAX_EXPIRY,
              ],
            }),
            chain: network.chain,
            type: "eip1559",
            gas: 300_000n,
            maxFeePerGas: fees.maxFeePerGas,
            maxPriorityFeePerGas: fees.maxPriorityFeePerGas,
          }),
        ),
      );

      console.log("sending chunk");
      const txs = await Promise.all(
        signedTransactions.map((tx) =>
          viem.walletClient.sendRawTransaction({
            serializedTransaction: tx,
          }),
        ),
      );

      // ensure txs are in mempool

      console.log("waiting for last transaction");
      // wait for the transaction with the highest nonce
      const run = async (): Promise<void> =>
        viem.publicClient
          .waitForTransactionReceipt({
            hash: txs[txs.length - 1],
            confirmations: 1,
            pollingInterval: network.tags.local ? 150 : 1_000,
            retryCount: 12,
          })
          .catch(async (e) => {
            if (e instanceof UserRejectedRequestError) {
              console.log("got user rejected request error, retrying");
              // ensure tx is in mempool
              const tx = await viem.publicClient.getTransaction({
                hash: txs[txs.length - 1],
              });
              console.log("tx in mempool", tx);
              if (!tx) throw new Error("tx not in mempool");
              return run();
            }
            throw e;
          })
          .then(() => undefined);
      await run();

      const checkAllSuccessful = async (): Promise<void> => {
        console.log("checking all were successful");
        await Promise.allSettled(
          txs.map((tx) =>
            viem.publicClient.getTransactionReceipt({
              hash: tx,
            }),
          ),
        ).then((receipts) => {
          for (let i = 0; i < receipts.length; i++) {
            const receipt = receipts[i];
            if (receipt.status === "rejected") {
              if (!(receipt.reason instanceof TransactionReceiptNotFoundError))
                throw receipt.reason;
              console.log("transaction not found, waiting then retrying");
              return viem.publicClient
                .waitForTransactionReceipt({
                  hash: txs[i],
                  confirmations: 1,
                  pollingInterval: network.tags.local ? 150 : 1_000,
                  retryCount: 12,
                })
                .then(() => checkAllSuccessful());
            } else {
              if (receipt.value.status !== "success")
                throw new Error(
                  `Transaction failed: ${receipt.value.status} / ${txs[i]}`,
                );
            }
          }
        });
      };
      await checkAllSuccessful();
    }

    // // Split suffixes into chunks of 100
    // const chunkSize = 100;
    // const suffixChunks: string[][] = [];
    // for (let i = 0; i < suffixes.length; i += chunkSize) {
    //   suffixChunks.push(suffixes.slice(i, i + chunkSize));
    // }

    // const

    // for (const chunk of suffixChunks) {

    //   await Promise.all(
    //     chunk.map((suffix) =>
    //       write(rootRegistry, {
    //         account: deployer,
    //         functionName: "register",
    //         args: [
    //           suffix,
    //           deployer, // TODO: ownership
    //           zeroAddress,
    //           dnsTLDResolver.address,
    //           0n, // TODO: roles
    //           MAX_EXPIRY,
    //         ],
    //       }),
    //     ),
    //   );
    // }

    // // TODO: this create 1000+ transactions
    // // batching is a mess in rocketh
    // // anvil batching appears broken (only mines 1-2 tx)
    // for (const suffix of suffixes) {
    //   await write(rootRegistry, {
    //     account: deployer,
    //     functionName: "register",
    //     args: [
    //       suffix,
    //       deployer, // TODO: ownership
    //       zeroAddress,
    //       dnsTLDResolver.address,
    //       0n, // TODO: roles
    //       MAX_EXPIRY,
    //     ],
    //   });
    // }
  },
  {
    tags: ["DNSTLDResolver", "l1"],
    dependencies: [
      "RootRegistry",
      "OffchainDNSResolver", // "ENSRegistry" + "DNSSECImpl"
      "SimplePublicSuffixList",
      "BatchGatewayProvider",
      "DNSSECGatewayProvider",
    ],
  },
);
