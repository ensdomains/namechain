import {
  type Abi,
  type Account,
  type Address,
  type Chain,
  type ContractFunctionName,
  encodeFunctionData,
  type EncodeFunctionDataParameters,
  getContract,
  keccak256,
  parseAbi,
  parseEventLogs,
  stringToBytes,
  type Transport,
  type WalletClient,
} from "viem";
import { waitForTransactionReceipt } from "viem/actions";

const verifiableFactoryAbi = parseAbi([
  "function deployProxy(address implementation, uint256 salt, bytes data)",
  "event ProxyDeployed(address indexed sender, address indexed proxyAddress, uint256 salt, address implementation)",
]);

export async function deployVerifiableProxy<
  const abi extends Abi | readonly unknown[],
  const functionName extends ContractFunctionName<abi> | undefined = undefined,
>({
  walletClient,
  factoryAddress,
  implAddress,
  salt = BigInt(keccak256(stringToBytes(new Date().toISOString()))),
  ...functionDataParameters
}: {
  walletClient: WalletClient<Transport, Chain, Account>;
  factoryAddress: Address;
  implAddress: Address;
  salt?: bigint;
} & EncodeFunctionDataParameters<abi, functionName>) {
  const hash = await walletClient.writeContract({
    address: factoryAddress,
    abi: verifiableFactoryAbi,
    functionName: "deployProxy",
    args: [
      implAddress,
      salt,
      encodeFunctionData(
        functionDataParameters as EncodeFunctionDataParameters,
      ),
    ],
  });
  const receipt = await waitForTransactionReceipt(walletClient, { hash });
  const [log] = parseEventLogs({
    abi: verifiableFactoryAbi,
    eventName: "ProxyDeployed",
    logs: receipt.logs,
  });
  const contract = getContract({
    abi: functionDataParameters.abi,
    address: log.args.proxyAddress,
    client: walletClient,
  });

  // Attach deployment metadata for gas tracking
  return Object.assign(contract, {
    deploymentHash: hash,
    deploymentReceipt: receipt,
  });
}
