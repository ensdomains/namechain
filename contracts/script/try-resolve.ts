import { loadDeployments, type Deployment } from "rocketh";
import {
  bytesToHex,
  createClient,
  decodeFunctionResult,
  encodeFunctionData,
  getContract,
  http,
  parseAbi,
  zeroHash,
  type Abi,
  type Hex,
} from "viem";
import { sepolia } from "viem/chains";

import type { artifacts } from "@rocketh";
import { privateKeyToAccount } from "viem/accounts";
import { packetToBytes } from "../test/utils/utils.ts";

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

const universalResolverDeployment = getDeployment<
  typeof artifacts.UniversalResolver.abi
>("l1", "UniversalResolverV2");
const universalResolver = getContract({
  abi: universalResolverDeployment.abi,
  address: universalResolverDeployment.address,
  client,
});

const result = await universalResolver.read.resolve([
  bytesToHex(packetToBytes("first-test.eth")),
  encodeFunctionData({
    abi: parseAbi([
      "function addr(bytes32, uint256 coinType) external view returns (bytes)",
    ]),
    functionName: "addr",
    args: [zeroHash, 60n],
  }),
]);
console.log("result", result);
const decoded = decodeFunctionResult({
  abi: parseAbi([
    "function addr(bytes32, uint256 coinType) external view returns (bytes)",
  ]),
  functionName: "addr",
  data: result[0],
});

console.log("result", decoded);
