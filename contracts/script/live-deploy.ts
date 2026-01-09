import { executeDeployScripts, loadDeployments, resolveConfig } from "rocketh";
import {
  createClient,
  createWalletClient,
  hexToNumber,
  http,
  nonceManager,
  type EIP1193RequestFn,
  type Hex,
  type WalletRpcSchema,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { prepareTransactionRequest, sendRawTransaction } from "viem/actions";
import { sepolia } from "viem/chains";

import { deployArtifact } from "../test/integration/fixtures/deployArtifact.js";
import { urgArtifact } from "../test/integration/fixtures/externalArtifacts.js";
import type { RockethArguments } from "./types.ts";

const chain = sepolia;
const rpcUrl = process.env.SEPOLIA_RPC_URL as string;

const client = createClient({
  chain,
  transport: http(rpcUrl),
});

process.env.BATCH_GATEWAY_URLS = '["x-batch-gateway:true"]';

type Signer = {
  request: EIP1193RequestFn<WalletRpcSchema>;
};

const getTransactionType = (params: unknown) => {
  const serializedType = (params as { type: Hex }).type;
  if (serializedType === "0x4") return "eip7702";
  if (serializedType === "0x3") return "eip4844";
  if (serializedType === "0x2") return "eip1559";
  if (serializedType === "0x1") return "eip2930";
  if (serializedType !== "0x" && hexToNumber(serializedType) >= 0xc0)
    return "legacy";
  throw new Error(`Unknown transaction type: ${serializedType}`);
};

const signer = (privKey: Hex): Signer => {
  const acc = privateKeyToAccount(privKey, { nonceManager: nonceManager });
  return {
    account: acc,
    request: async (request) => {
      if (request.method === "eth_sendTransaction") {
        for (const [key, value] of Object.entries(request.params[0])) {
          if (value === undefined) {
            delete request.params[0][key];
          }
        }
        const prepared = await prepareTransactionRequest(client, {
          ...request.params[0],
          type: getTransactionType(request.params[0]),
          nonceManager: nonceManager,
          account: acc,
        });
        console.log(Object.keys(prepared));
        const signed = await acc.signTransaction(prepared);
        const hash = await sendRawTransaction(client, {
          serializedTransaction: signed,
        });
        return hash;
      }
      if (request.method === "eth_accounts") {
        return [acc.address];
      }
      throw new Error(`Unknown method: ${request.method}`);
    },
  };
};

const privateKey = async (protocolString: string) => {
  const [proto, privateKeyString] = protocolString.split(":");
  if (!privateKeyString.startsWith("0x")) {
    throw new Error(`Private key must start with 0x, got: ${privateKeyString}`);
  }
  const privateKey = privateKeyString;
  return {
    type: "wallet",
    signer: signer(privateKey as Hex),
  } as const;
};

const runDeploy = async (
  scripts: string[],
  tags: string[],
  deployments: string,
  args?: RockethArguments,
) => {
  return executeDeployScripts(
    resolveConfig({
      logLevel: 1,
      network: {
        nodeUrl: rpcUrl,
        name: "sepoliaFresh",
        fork: false,
        scripts,
        tags,
        publicInfo: {
          name: "sepolia",
          nativeCurrency: chain.nativeCurrency,
          rpcUrls: { default: { http: [...chain.rpcUrls.default.http] } },
        },
        provider: http(rpcUrl)({ chain }),
      },
      askBeforeProceeding: false,
      saveDeployments: true,
      accounts: {
        deployer: process.env.DEPLOYER_KEY as Hex,
        owner: process.env.DEPLOYER_KEY as Hex,
      },
      deployments,
      signerProtocols: {
        privateKey,
      },
    }),
    args,
  );
};

const deployUnrug = async () => {
  const walletClient = createWalletClient({
    chain,
    transport: http(rpcUrl),
    account: privateKeyToAccount(process.env.DEPLOYER_KEY as Hex, {
      nonceManager: nonceManager,
    }),
  });

  console.log("Deploying GatewayVM...");
  const GatewayVM = await deployArtifact(walletClient, {
    file: urgArtifact("GatewayVM"),
  });
  console.log("GatewayVM deployed to", GatewayVM);

  console.log("Deploying EthHookVerifier...");
  const ethHookVerifier = await deployArtifact(walletClient, {
    file: urgArtifact("EthVerifierHooks"),
  });
  console.log("EthHookVerifier deployed to", ethHookVerifier);

  console.log("Deploying SelfVerifier...");
  const selfVerifier = await deployArtifact(walletClient, {
    file: urgArtifact("SelfVerifier"),
    args: [
      ["https://gateways-worker-sepolia.ens-cf.workers.dev"],
      60,
      ethHookVerifier,
    ],
    libs: { GatewayVM },
  });
  console.log("SelfVerifier deployed to", selfVerifier);
  return selfVerifier;
};

const GatewayVM = "0x31FF4C757ea3C0517bF5148058C611e884B14Ca2";
const EthHookVerifier = "0x088Bd87C93C06EEB184C82ff987Faf7Aa28aE6f7";
const selfVerifier = "0x8eA3957bF696bB81523E6b9Cdf3fac8A57C14f0e"; // await deployUnrug();

const runV1L1Deploy = async () => {
  console.log("Running V1 L1 deploy");

  const v1L1Deploy = await runDeploy(
    ["lib/ens-contracts/deploy"],
    ["use_root", "allow_unsafe", "legacy"],
    "deployments/l1/v1",
  );
};

// // copy BatchGatewayProvider since it's reused by v2 deploy scripts
// await $`mkdir -p deployments/l1/sepoliaFresh`;
// await $`cp deployments/l1/v1/sepoliaFresh/.chain deployments/l1/v1/sepoliaFresh/BatchGatewayProvider.json deployments/l1/sepoliaFresh`;

const runL2Deploy = async () => {
  console.log("Running L2 deploy");

  const l2Deploy = await runDeploy(
    ["deploy/l2", "deploy/shared"],
    ["l2"],
    "deployments/l2",
  );
};

const runL1Deploy = async () => {
  console.log("Running L1 deploy");
  const l2Deploy = loadDeployments("deployments/l2", "sepoliaFresh", true);

  // local tag for URv2 on UURP
  const l1Deploy = await runDeploy(
    ["deploy/l1", "deploy/shared"],
    ["l1", "local"],
    "deployments/l1",
    {
      l2Deploy,
      verifierAddress: selfVerifier,
    },
  );
};

await runL1Deploy();
