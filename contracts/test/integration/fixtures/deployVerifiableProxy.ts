import {
  type Abi,
  type Account,
  type Address,
  type Chain,
  type Hex,
  type Transport,
  type WalletClient,
  keccak256,
  stringToBytes,
  parseEventLogs,
  getContract,
  encodeFunctionData,
  parseAbi,
} from "viem";
import { waitForTransactionReceipt } from "viem/actions";

const verifiableFactoryAbi = parseAbi([
  "function deployProxy(address implementation, uint256 salt, bytes data)",
  "event ProxyDeployed(address indexed sender, address indexed proxyAddress, uint256 salt, address implementation)",
]);

export async function deployVerifiableProxy({
  walletClient,
  factoryAddress,
  implAddress,
  implAbi,
  callData,
  salt = BigInt(keccak256(stringToBytes(new Date().toISOString()))),
}: {
  walletClient: WalletClient<Transport, Chain, Account>;
  factoryAddress: Address;
  implAddress: Address;
  implAbi: Abi;
  callData?: Hex;
  salt?: bigint;
}) {
  callData ??= encodeFunctionData({
    abi: parseAbi(["function initialize(address)"]),
    functionName: "initialize",
    args: [walletClient.account.address],
  });
  const hash = await walletClient.writeContract({
    address: factoryAddress,
    abi: verifiableFactoryAbi,
    functionName: "deployProxy",
    args: [implAddress, salt, callData],
  });
  const receipt = await waitForTransactionReceipt(walletClient, { hash });
  const [log] = parseEventLogs({
    abi: verifiableFactoryAbi,
	eventName: 'ProxyDeployed',
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
    deploymentReceipt: receipt
  });
}
