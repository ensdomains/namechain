import { createPublicClient, http, type Chain, getContract, type Log, decodeEventLog, type Abi, type DecodeEventLogReturnType, encodeFunctionData, parseEventLogs } from "viem";
import { readFileSync } from "fs";
import { join } from "path";
import { privateKeyToAccount, mnemonicToAccount } from "viem/accounts";

// Define chain types
const l1Chain: Chain = {
  id: 31337,
  name: "Local L1",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: ["http://127.0.0.1:8545"] },
    public: { http: ["http://127.0.0.1:8545"] },
  },
};

const l2Chain: Chain = {
  id: 31338,
  name: "Local L2",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: ["http://127.0.0.1:8546"] },
    public: { http: ["http://127.0.0.1:8546"] },
  },
};

// Connect to the networks
const l1Client = createPublicClient({
  chain: l1Chain,
  transport: http(),
});

const l2Client = createPublicClient({
  chain: l2Chain,
  transport: http(),
});

// Read deployment files
const rootRegistryPath = join(process.cwd(), "deployments", "l1-local", "RootRegistry.json");
const l1EthRegistryPath = join(process.cwd(), "deployments", "l1-local", "L1ETHRegistry.json");
const ethRegistryPath = join(process.cwd(), "deployments", "l2-local", "ETHRegistry.json");
const verifiableFactoryPath = join(process.cwd(), "deployments", "l2-local", "VerifiableFactory.json");
const dedicatedResolverImplPath = join(process.cwd(), "deployments", "l2-local", "DedicatedResolverImpl.json");

const rootRegistryDeployment = JSON.parse(readFileSync(rootRegistryPath, "utf8"));
const l1EthRegistryDeployment = JSON.parse(readFileSync(l1EthRegistryPath, "utf8"));
const ethRegistryDeployment = JSON.parse(readFileSync(ethRegistryPath, "utf8"));
const verifiableFactoryDeployment = JSON.parse(readFileSync(verifiableFactoryPath, "utf8"));
const dedicatedResolverImplDeployment = JSON.parse(readFileSync(dedicatedResolverImplPath, "utf8"));

const resolverAddresses = new Set<string>();

async function waitForTransaction(hash: `0x${string}`) {
  while (true) {
    try {
      const receipt = await l2Client.getTransactionReceipt({ hash });
      if (receipt) return receipt;
    } catch (error) {
      // Transaction not found yet, wait and retry
      await new Promise(resolve => setTimeout(resolve, 1000));
    }
  }
}

function decodeEvent(log: Log, abi: Abi) {
  try {
    return decodeEventLog({
      abi,
      data: log.data,
      topics: log.topics,
    });
  } catch (error) {
    return null;
  }
}

function formatEventLog(log: Log, abi: Abi) {
  const decoded = decodeEvent(log, abi);
  if (!decoded) {
    return {
      eventName: "Unknown Event",
      args: "Failed to decode event data",
    };
  }

  return {
    eventName: decoded.eventName,
    args: decoded.args,
  };
}

async function deployDedicatedResolver(name: string, owner: `0x${string}`, account: any) {
  const verifiableFactory = getContract({
    address: verifiableFactoryDeployment.address,
    abi: verifiableFactoryDeployment.abi,
    client: l2Client,
  });

  const salt = BigInt(Date.now());
  const initData = encodeFunctionData({
    abi: dedicatedResolverImplDeployment.abi,
    functionName: "initialize",
    args: [owner],
  });

  const hash = await verifiableFactory.write.deployProxy(
    [dedicatedResolverImplDeployment.address, salt, initData],
    { account }
  );

  // Wait for the transaction to be mined
  const receipt = await waitForTransaction(hash);
  const logs = parseEventLogs({
    abi: verifiableFactoryDeployment.abi,
    eventName: "ProxyDeployed",
    logs: receipt.logs,
  }) as unknown as [{ args: { proxyAddress: `0x${string}` } }];

  if (!logs.length) {
    throw new Error("No ProxyDeployed event found");
  }

  return logs[0].args.proxyAddress;
}

async function registerNames() {
  // Create an account from the default mnemonic
  const account = mnemonicToAccount("test test test test test test test test test test test junk");

  // Define the names to register
  const names = ["test1", "test2", "test3"];
  
  // Get the L2 registry
  const ethRegistry = getContract({
    address: ethRegistryDeployment.address,
    abi: ethRegistryDeployment.abi,
    client: l2Client,
  });

  // Register names on L2
  console.log("Registering names on L2...");
  for (const name of names) {
    // Deploy a DedicatedResolver for this name
    console.log(`Deploying DedicatedResolver for ${name}...`);
    const resolverAddress = await deployDedicatedResolver(name, account.address, account);
    console.log(`DedicatedResolver deployed at ${resolverAddress}`);

    // Set the ETH address in the resolver
    const dedicatedResolver = getContract({
      address: resolverAddress,
      abi: dedicatedResolverImplDeployment.abi,
      client: l2Client,
    });

    // Get the resolver address (you might want to deploy a dedicated resolver)
    const zeroAddress = "0x0000000000000000000000000000000000000000";

    // Register names
    console.log(`Registering ${name}...`);
    const tx = await ethRegistry.write.register(
      [
        name,
        account.address,
        zeroAddress,
        dedicatedResolver.address,
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffn, // All roles
        0xffffffffffffffffn, // MAX_EXPIRY
      ],
      { account }
    );
    await waitForTransaction(tx);

    console.log(`Transaction hash: ${tx}`);
    const result = await ethRegistry.read.getNameData([name]) as [bigint, bigint, number];
    const [tokenId, expiry, tokenIdVersion] = result;

    console.log(`Setting ETH address for ${name}...`);
    await dedicatedResolver.write.setAddr(
      [60n, account.address],
      { account }
    );
    console.log(`Setting TEXT record for ${name}...`);
    await dedicatedResolver.write.setText(
      ["domain", name],
      { account }
    );

    console.log(`Token ID: ${tokenId}`);
    console.log(`Expiry: ${expiry}`);
    console.log(`Token ID Version: ${tokenIdVersion}`);
  }

  console.log("\nAll Resolver Addresses Set via ResolverUpdate:");
  console.log("----------------");
  if (resolverAddresses.size === 0) {
    console.log("No resolver addresses found.");
  } else {
    resolverAddresses.forEach(resolver => {
      console.log(`- ${resolver}`);
    });
  }
  console.log("----------------");
  console.log(`Total unique resolver addresses: ${resolverAddresses.size}`);
}

registerNames();