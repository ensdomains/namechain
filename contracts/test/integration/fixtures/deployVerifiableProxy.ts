import {
  type Abi,
  type Account,
  type Address,
  type Chain,
  type Transport,
  type WalletClient,
  type ContractFunctionName,
  type ContractFunctionArgs,
  keccak256,
  stringToBytes,
  parseEventLogs,
  getContract,
  parseAbi,
  encodeFunctionData,
  AbiStateMutability,
} from "viem";
import { waitForTransactionReceipt } from "viem/actions";

const verifiableFactoryAbi = parseAbi([
  "function deployProxy(address implementation, uint256 salt, bytes data)",
  "event ProxyDeployed(address indexed sender, address indexed proxyAddress, uint256 salt, address implementation)",
]);

export async function deployVerifiableProxy<
  const TAbi extends Abi,
  TMut extends AbiStateMutability,
  TFn extends ContractFunctionName<TAbi>,
>({
  walletClient,
  factoryAddress,
  implAddress,
  implAbi,
  functionName,
  args,
  salt = BigInt(keccak256(stringToBytes(new Date().toISOString()))),
}: {
  walletClient: WalletClient<Transport, Chain, Account>;
  factoryAddress: Address;
  implAddress: Address;
  implAbi: TAbi;
  functionName: TFn;
  args: ContractFunctionArgs<TAbi, TMut, TFn>;
  salt?: bigint;
}) {
  const hash = await walletClient.writeContract({
    address: factoryAddress,
    abi: verifiableFactoryAbi,
    functionName: "deployProxy",
    args: [
      implAddress,
      salt,
      encodeFunctionData({
        abi: implAbi as any, // typechecked at callsite
        functionName,
        args: args as any,
      }),
    ],
  });
  const receipt = await waitForTransactionReceipt(walletClient, { hash });
  const [log] = parseEventLogs({
    abi: verifiableFactoryAbi,
    eventName: "ProxyDeployed",
    logs: receipt.logs,
  });
  const contract = getContract({
    abi: implAbi,
    address: log.args.proxyAddress,
    client: walletClient,
  });

  // Attach deployment metadata for gas tracking
  return Object.assign(contract, {
    deploymentHash: hash,
    deploymentReceipt: receipt,
  });
}
