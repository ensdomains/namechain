import { loadDeployments, type Deployment } from "rocketh";
import {
  createClient,
  getContract,
  http,
  zeroHash,
  type Abi,
  type Hex,
} from "viem";
import { sepolia } from "viem/chains";

import type { artifacts } from "@rocketh";
import { privateKeyToAccount } from "viem/accounts";
import { waitForTransactionReceipt } from "viem/actions";

const chainName = "sepoliaFresh";
const deployments = {
  v1: loadDeployments("deployments/l1/v1", chainName, false).deployments,
  l1: loadDeployments("deployments/l1", chainName, false).deployments,
  l2: loadDeployments("deployments/l2", chainName, false).deployments,
} as const;
const getDeployment = <TAbi extends Abi>(
  from: keyof typeof deployments,
  path: string,
): Deployment<TAbi> => {
  const deployment =
    deployments[from][path as keyof (typeof deployments)[typeof from]];
  console.log(Object.keys(deployments[from]));
  if (!deployment) throw new Error(`Deployment ${path} not found`);
  return deployment as Deployment<TAbi>;
};

const client = createClient({
  chain: sepolia,
  transport: http(process.env.SEPOLIA_RPC_URL as string),
  account: privateKeyToAccount(process.env.NAME_OWNER_KEY as Hex),
});

const dedicatedResolverImplDeployment = getDeployment<
  typeof artifacts.DedicatedResolver.abi
>("l2", "DedicatedResolverImpl");
const dedicatedResolver = getContract({
  abi: dedicatedResolverImplDeployment.abi,
  address: "0xd7695e331224103d0dce7f443610c816f0e91ad9",
  client,
});

const tx = await dedicatedResolver.write.setAddr([60n, client.account.address]);

const receipt = await waitForTransactionReceipt(client, { hash: tx });
if (receipt.status !== "success") throw new Error("Failed to set addr");

console.log("Address set");

const addr = await dedicatedResolver.read.addr([zeroHash]);
console.log("addr", addr);
