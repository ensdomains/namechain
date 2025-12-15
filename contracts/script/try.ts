import { loadDeployments, type Deployment } from "rocketh";
import {
  createClient,
  encodeFunctionData,
  getContract,
  http,
  parseEventLogs,
  zeroAddress,
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
  account: privateKeyToAccount(process.env.DEPLOYER_KEY as Hex),
});

const ethRegistryDeployment = getDeployment<
  typeof artifacts.PermissionedRegistry.abi
>("l2", "ETHRegistry");
const ethRegistry = getContract({
  abi: ethRegistryDeployment.abi,
  address: ethRegistryDeployment.address,
  client,
});

const dedicatedResolverImplDeployment = getDeployment<
  typeof artifacts.DedicatedResolver.abi
>("l2", "DedicatedResolverImpl");

const verifiableFactoryDeployment = getDeployment<
  typeof artifacts.VerifiableFactory.abi
>("l2", "VerifiableFactory");
const verifiableFactory = getContract({
  abi: verifiableFactoryDeployment.abi,
  address: verifiableFactoryDeployment.address,
  client,
});

const label = "first-test";
const nameOwner = "0x69420f05A11f617B4B74fFe2E04B2D300dFA556F";

const deployProxyHash = await verifiableFactory.write.deployProxy([
  dedicatedResolverImplDeployment.address,
  1n,
  encodeFunctionData({
    abi: dedicatedResolverImplDeployment.abi,
    functionName: "initialize",
    args: [nameOwner],
  }),
]);

const deployProxyReceipt = await waitForTransactionReceipt(client, {
  hash: deployProxyHash,
});
if (deployProxyReceipt.status !== "success")
  throw new Error("Proxy deployment failed");

const [log] = parseEventLogs({
  abi: verifiableFactoryDeployment.abi,
  eventName: "ProxyDeployed",
  logs: deployProxyReceipt.logs,
});
const dedicatedResolverAddress = log.args.proxyAddress;

const tx = await ethRegistry.write.register([
  "first-test",
  nameOwner,
  zeroAddress,
  dedicatedResolverAddress,
  0n,
  BigInt(Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 365),
]);

const registerReceipt = await waitForTransactionReceipt(client, { hash: tx });
if (registerReceipt.status !== "success")
  throw new Error("Name registration failed");

const [tokenId] = await ethRegistry.read.getNameData([label]);
console.log("tokenId", tokenId);

const owner = await ethRegistry.read.ownerOf([tokenId]);
console.log("owner", owner);
