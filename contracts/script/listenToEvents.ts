import { createPublicClient, http, type Chain, getContract, type Log, decodeEventLog } from "viem";
import { readFileSync } from "fs";
import { join } from "path";

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
const l1RegistryDatastorePath = join(process.cwd(), "deployments", "l1-local", "RegistryDatastore.json");
const l2RegistryDatastorePath = join(process.cwd(), "deployments", "l2-local", "RegistryDatastore.json");
const dedicatedResolverImplPath = join(process.cwd(), "deployments", "l2-local", "DedicatedResolverImpl.json");

const rootRegistryDeployment = JSON.parse(readFileSync(rootRegistryPath, "utf8"));
const l1EthRegistryDeployment = JSON.parse(readFileSync(l1EthRegistryPath, "utf8"));
const ethRegistryDeployment = JSON.parse(readFileSync(ethRegistryPath, "utf8"));
const l1RegistryDatastoreDeployment = JSON.parse(readFileSync(l1RegistryDatastorePath, "utf8"));
const l2RegistryDatastoreDeployment = JSON.parse(readFileSync(l2RegistryDatastorePath, "utf8"));
const dedicatedResolverImplDeployment = JSON.parse(readFileSync(dedicatedResolverImplPath, "utf8"));

// Event ABIs
const registryEvents = [
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "oldTokenId", type: "uint256" },
      { indexed: true, name: "newTokenId", type: "uint256" }
    ],
    name: "TokenRegenerated",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "tokenId", type: "uint256" },
      { indexed: false, name: "label", type: "string" }
    ],
    name: "NewSubname",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "tokenId", type: "uint256" },
      { indexed: false, name: "expires", type: "uint64" },
      { indexed: true, name: "sender", type: "address" }
    ],
    name: "NameRenewed",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "tokenId", type: "uint256" },
      { indexed: true, name: "sender", type: "address" }
    ],
    name: "NameRelinquished",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "tokenId", type: "uint256" },
      { indexed: true, name: "observer", type: "address" }
    ],
    name: "TokenObserverSet",
    type: "event"
  },
  // ERC1155 Events
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "operator", type: "address" },
      { indexed: true, name: "from", type: "address" },
      { indexed: true, name: "to", type: "address" },
      { indexed: false, name: "id", type: "uint256" },
      { indexed: false, name: "value", type: "uint256" }
    ],
    name: "TransferSingle",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "operator", type: "address" },
      { indexed: true, name: "from", type: "address" },
      { indexed: true, name: "to", type: "address" },
      { indexed: false, name: "ids", type: "uint256[]" },
      { indexed: false, name: "values", type: "uint256[]" }
    ],
    name: "TransferBatch",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "account", type: "address" },
      { indexed: true, name: "operator", type: "address" },
      { indexed: false, name: "approved", type: "bool" }
    ],
    name: "ApprovalForAll",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: false, name: "value", type: "string" },
      { indexed: true, name: "id", type: "uint256" }
    ],
    name: "URI",
    type: "event"
  },
  // ETHRegistrar Events
  {
    anonymous: false,
    inputs: [
      { indexed: false, name: "name", type: "string" },
      { indexed: true, name: "owner", type: "address" },
      { indexed: false, name: "subregistry", type: "address" },
      { indexed: false, name: "resolver", type: "address" },
      { indexed: false, name: "duration", type: "uint64" },
      { indexed: false, name: "tokenId", type: "uint256" }
    ],
    name: "NameRegistered",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: false, name: "name", type: "string" },
      { indexed: false, name: "duration", type: "uint64" },
      { indexed: false, name: "tokenId", type: "uint256" },
      { indexed: false, name: "newExpiry", type: "uint64" }
    ],
    name: "NameRenewed",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: false, name: "commitment", type: "bytes32" }
    ],
    name: "CommitmentMade",
    type: "event"
  }
] as const;

const datastoreEvents = [
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "registry", type: "address" },
      { indexed: true, name: "id", type: "uint256" },
      { indexed: false, name: "subregistry", type: "address" },
      { indexed: false, name: "expiry", type: "uint64" },
      { indexed: false, name: "data", type: "uint32" }
    ],
    name: "SubregistryUpdate",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "registry", type: "address" },
      { indexed: true, name: "id", type: "uint256" },
      { indexed: false, name: "resolver", type: "address" },
      { indexed: false, name: "expiry", type: "uint64" },
      { indexed: false, name: "data", type: "uint32" }
    ],
    name: "ResolverUpdate",
    type: "event"
  }
] as const;

const dedicatedResolverEvents = [
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "node", type: "bytes32" },
      { indexed: false, name: "coinType", type: "uint256" },
      { indexed: false, name: "newAddress", type: "bytes" }
    ],
    name: "AddressChanged",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "node", type: "bytes32" },
      { indexed: false, name: "x", type: "bytes32" },
      { indexed: false, name: "y", type: "bytes32" }
    ],
    name: "PubkeyChanged",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "node", type: "bytes32" },
      { indexed: false, name: "hash", type: "bytes" }
    ],
    name: "ContenthashChanged",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "node", type: "bytes32" },
      { indexed: false, name: "name", type: "string" }
    ],
    name: "NameChanged",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "node", type: "bytes32" },
      { indexed: false, name: "key", type: "string" },
      { indexed: false, name: "indexedKey", type: "string" },
      { indexed: false, name: "value", type: "string" }
    ],
    name: "TextChanged",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "node", type: "bytes32" },
      { indexed: false, name: "contentType", type: "uint256" }
    ],
    name: "ABIChanged",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "node", type: "bytes32" },
      { indexed: true, name: "interfaceID", type: "bytes4" },
      { indexed: false, name: "implementer", type: "address" }
    ],
    name: "InterfaceChanged",
    type: "event"
  }
] as const;

// Get the datastore address from RootRegistry
const rootRegistryABI = [
  {
    inputs: [],
    name: "datastore",
    outputs: [{ type: "address", name: "" }],
    stateMutability: "view",
    type: "function",
  },
] as const;

function decodeEvent(log: Log, events: typeof registryEvents | typeof datastoreEvents | typeof dedicatedResolverEvents) {
  try {
    const decoded = decodeEventLog({
      abi: events,
      data: log.data,
      topics: log.topics,
    });
    return decoded;
  } catch (error) {
    return null;
  }
}

function formatEventLog(log: Log, events: typeof registryEvents | typeof datastoreEvents | typeof dedicatedResolverEvents, chain: string, contractName: string, contractAddress: string) {
  const decoded = decodeEvent(log, events);
  if (!decoded) {
    return {
      eventName: "Unknown Event",
      args: "Failed to decode event data",
      chain,
      contractName,
      contractAddress,
    };
  }

  return {
    eventName: decoded.eventName,
    args: decoded.args,
    chain,
    contractName,
    contractAddress,
  };
}

// Keep track of active resolvers
const activeResolvers = new Set<`0x${string}`>();

async function listenToEvents() {
  console.log("Starting to listen to registry and resolver events...\n");
  
  // Display contract addresses
  console.log("Contract Addresses:");
  console.log("-------------------");
  console.log(`RootRegistry: ${rootRegistryDeployment.address}`);
  console.log(`L1ETHRegistry: ${l1EthRegistryDeployment.address}`);
  console.log(`ETHRegistry: ${ethRegistryDeployment.address}`);
  console.log(`L1 RegistryDatastore: ${l1RegistryDatastoreDeployment.address}`);
  console.log(`L2 RegistryDatastore: ${l2RegistryDatastoreDeployment.address}`);
  console.log(`DedicatedResolverImpl: ${dedicatedResolverImplDeployment.address}`);

  // Get the datastore address from RootRegistry
  const rootRegistry = getContract({
    address: rootRegistryDeployment.address,
    abi: rootRegistryABI,
    client: l1Client,
  });

  const rootRegistryDatastore = await rootRegistry.read.datastore();
  console.log(`RootRegistry's Datastore: ${rootRegistryDatastore}`);
  console.log("-------------------\n");

  // Get current block numbers
  const l1Block = await l1Client.getBlockNumber();
  const l2Block = await l2Client.getBlockNumber();
  console.log(`Current L1 Block: ${l1Block}`);
  console.log(`Current L2 Block: ${l2Block}\n`);

  // Fetch historical events
  console.log("Fetching historical events...\n");

  // RootRegistry historical events
  const rootRegistryLogs = await l1Client.getLogs({
    address: rootRegistryDeployment.address,
    fromBlock: 0n,
    toBlock: l1Block,
  });
  if (rootRegistryLogs.length > 0) {
    console.log("\nHistorical RootRegistry Events:");
    rootRegistryLogs.forEach(log => {
      const { eventName, args, chain, contractName, contractAddress } = formatEventLog(log, registryEvents, "L1", "RootRegistry", rootRegistryDeployment.address);
      console.log(`- Event: ${eventName}`);
      console.log(`- Chain: ${chain} (${contractName} - ${contractAddress})`);
      console.log(`- Transaction: ${log.transactionHash}`);
      console.log(`- Block: ${log.blockNumber}`);
      console.log(`- Arguments:`, args);
    });
  }

  // L1ETHRegistry historical events
  const l1EthRegistryLogs = await l1Client.getLogs({
    address: l1EthRegistryDeployment.address,
    fromBlock: 0n,
    toBlock: l1Block,
  });
  if (l1EthRegistryLogs.length > 0) {
    console.log("\nHistorical L1ETHRegistry Events:");
    l1EthRegistryLogs.forEach(log => {
      const { eventName, args, chain, contractName, contractAddress } = formatEventLog(log, registryEvents, "L1", "L1ETHRegistry", l1EthRegistryDeployment.address);
      console.log(`- Event: ${eventName}`);
      console.log(`- Chain: ${chain} (${contractName} - ${contractAddress})`);
      console.log(`- Transaction: ${log.transactionHash}`);
      console.log(`- Block: ${log.blockNumber}`);
      console.log(`- Arguments:`, args);
    });
  }

  // ETHRegistry historical events
  const ethRegistryLogs = await l2Client.getLogs({
    address: ethRegistryDeployment.address,
    fromBlock: 0n,
    toBlock: l2Block,
  });
  if (ethRegistryLogs.length > 0) {
    console.log("\nHistorical ETHRegistry Events:");
    ethRegistryLogs.forEach(log => {
      const { eventName, args, chain, contractName, contractAddress } = formatEventLog(log, registryEvents, "L2", "ETHRegistry", ethRegistryDeployment.address);
      console.log(`- Event: ${eventName}`);
      console.log(`- Chain: ${chain} (${contractName} - ${contractAddress})`);
      console.log(`- Transaction: ${log.transactionHash}`);
      console.log(`- Block: ${log.blockNumber}`);
      console.log(`- Arguments:`, args);
    });
  }

  // RegistryDatastore historical events (L1)
  const l1DatastoreLogs = await l1Client.getLogs({
    address: l1RegistryDatastoreDeployment.address,
    fromBlock: 0n,
    toBlock: l1Block,
  });
  if (l1DatastoreLogs.length > 0) {
    console.log("\nHistorical RegistryDatastore Events (L1):");
    l1DatastoreLogs.forEach(log => {
      const { eventName, args, chain, contractName, contractAddress } = formatEventLog(log, datastoreEvents, "L1", "RegistryDatastore", l1RegistryDatastoreDeployment.address);
      console.log(`- Event: ${eventName}`);
      console.log(`- Chain: ${chain} (${contractName} - ${contractAddress})`);
      console.log(`- Transaction: ${log.transactionHash}`);
      console.log(`- Block: ${log.blockNumber}`);
      console.log(`- Arguments:`, args);

      // If this is a ResolverUpdate event, add the resolver to our tracking set
      if (eventName === "ResolverUpdate" && typeof args === 'object' && args !== null && 'resolver' in args && typeof args.resolver === 'string') {
        activeResolvers.add(args.resolver as `0x${string}`);
      }
    });
  }

  // RegistryDatastore historical events (L2)
  const l2DatastoreLogs = await l2Client.getLogs({
    address: l2RegistryDatastoreDeployment.address,
    fromBlock: 0n,
    toBlock: l2Block,
  });
  if (l2DatastoreLogs.length > 0) {
    console.log("\nHistorical RegistryDatastore Events (L2):");
    l2DatastoreLogs.forEach(log => {
      const { eventName, args, chain, contractName, contractAddress } = formatEventLog(log, datastoreEvents, "L2", "RegistryDatastore", l2RegistryDatastoreDeployment.address);
      console.log(`- Event: ${eventName}`);
      console.log(`- Chain: ${chain} (${contractName} - ${contractAddress})`);
      console.log(`- Transaction: ${log.transactionHash}`);
      console.log(`- Block: ${log.blockNumber}`);
      console.log(`- Arguments:`, args);

      // If this is a ResolverUpdate event, add the resolver to our tracking set
      if (eventName === "ResolverUpdate" && typeof args === 'object' && args !== null && 'resolver' in args && typeof args.resolver === 'string') {
        activeResolvers.add(args.resolver as `0x${string}`);
      }
    });
  }

  // Fetch historical events for all active resolvers
  for (const resolverAddress of activeResolvers) {
    const resolverLogs = await l2Client.getLogs({
      address: resolverAddress,
      fromBlock: 0n,
      toBlock: l2Block,
    });
    if (resolverLogs.length > 0) {
      console.log(`\nHistorical Events for Resolver ${resolverAddress}:`);
      resolverLogs.forEach(log => {
        const { eventName, args, chain, contractName, contractAddress } = formatEventLog(log, dedicatedResolverEvents, "L2", "DedicatedResolver", resolverAddress);
        console.log(`- Event: ${eventName}`);
        console.log(`- Chain: ${chain} (${contractName} - ${contractAddress})`);
        console.log(`- Transaction: ${log.transactionHash}`);
        console.log(`- Block: ${log.blockNumber}`);
        console.log(`- Arguments:`, args);
      });
    }
  }

  console.log("\nNow listening for new events...\n");

  // Start listening for new events
  let lastRootRegistryBlock = l1Block;
  let lastL1EthRegistryBlock = l1Block;
  let lastEthRegistryBlock = l2Block;
  let lastL1DatastoreBlock = l1Block;
  let lastL2DatastoreBlock = l2Block;
  const lastResolverBlocks = new Map<`0x${string}`, bigint>();

  // Initialize last block for each active resolver
  for (const resolverAddress of activeResolvers) {
    lastResolverBlocks.set(resolverAddress, l2Block);
  }

  setInterval(async () => {
    // RootRegistry
    const latestRootRegistryBlock = await l1Client.getBlockNumber();
    if (latestRootRegistryBlock > lastRootRegistryBlock) {
      const logs = await l1Client.getLogs({
        address: rootRegistryDeployment.address,
        fromBlock: lastRootRegistryBlock + 1n,
        toBlock: latestRootRegistryBlock,
      });
      if (logs.length > 0) {
        console.log("\nNew RootRegistry Events:");
        logs.forEach(log => {
          const { eventName, args, chain, contractName, contractAddress } = formatEventLog(log, registryEvents, "L1", "RootRegistry", rootRegistryDeployment.address);
          console.log(`- Event: ${eventName}`);
          console.log(`- Chain: ${chain} (${contractName} - ${contractAddress})`);
          console.log(`- Transaction: ${log.transactionHash}`);
          console.log(`- Block: ${log.blockNumber}`);
          console.log(`- Arguments:`, args);
        });
      }
      lastRootRegistryBlock = latestRootRegistryBlock;
    }

    // L1ETHRegistry
    const latestL1EthRegistryBlock = await l1Client.getBlockNumber();
    if (latestL1EthRegistryBlock > lastL1EthRegistryBlock) {
      const logs = await l1Client.getLogs({
        address: l1EthRegistryDeployment.address,
        fromBlock: lastL1EthRegistryBlock + 1n,
        toBlock: latestL1EthRegistryBlock,
      });
      if (logs.length > 0) {
        console.log("\nNew L1ETHRegistry Events:");
        logs.forEach(log => {
          const { eventName, args, chain, contractName, contractAddress } = formatEventLog(log, registryEvents, "L1", "L1ETHRegistry", l1EthRegistryDeployment.address);
          console.log(`- Event: ${eventName}`);
          console.log(`- Chain: ${chain} (${contractName} - ${contractAddress})`);
          console.log(`- Transaction: ${log.transactionHash}`);
          console.log(`- Block: ${log.blockNumber}`);
          console.log(`- Arguments:`, args);
        });
      }
      lastL1EthRegistryBlock = latestL1EthRegistryBlock;
    }

    // ETHRegistry (L2)
    const latestEthRegistryBlock = await l2Client.getBlockNumber();
    if (latestEthRegistryBlock > lastEthRegistryBlock) {
      const logs = await l2Client.getLogs({
        address: ethRegistryDeployment.address,
        fromBlock: lastEthRegistryBlock + 1n,
        toBlock: latestEthRegistryBlock,
      });
      if (logs.length > 0) {
        console.log("\nNew ETHRegistry Events:");
        logs.forEach(log => {
          const { eventName, args, chain, contractName, contractAddress } = formatEventLog(log, registryEvents, "L2", "ETHRegistry", ethRegistryDeployment.address);
          console.log(`- Event: ${eventName}`);
          console.log(`- Chain: ${chain} (${contractName} - ${contractAddress})`);
          console.log(`- Transaction: ${log.transactionHash}`);
          console.log(`- Block: ${log.blockNumber}`);
          console.log(`- Arguments:`, args);
        });
      }
      lastEthRegistryBlock = latestEthRegistryBlock;
    }

    // RegistryDatastore (L1)
    const latestL1DatastoreBlock = await l1Client.getBlockNumber();
    if (latestL1DatastoreBlock > lastL1DatastoreBlock) {
      const logs = await l1Client.getLogs({
        address: l1RegistryDatastoreDeployment.address,
        fromBlock: lastL1DatastoreBlock + 1n,
        toBlock: latestL1DatastoreBlock,
      });
      if (logs.length > 0) {
        console.log("\nNew RegistryDatastore Events (L1):");
        logs.forEach(log => {
          const { eventName, args, chain, contractName, contractAddress } = formatEventLog(log, datastoreEvents, "L1", "RegistryDatastore", l1RegistryDatastoreDeployment.address);
          console.log(`- Event: ${eventName}`);
          console.log(`- Chain: ${chain} (${contractName} - ${contractAddress})`);
          console.log(`- Transaction: ${log.transactionHash}`);
          console.log(`- Block: ${log.blockNumber}`);
          console.log(`- Arguments:`, args);

          // If this is a ResolverUpdate event, add the resolver to our tracking set
          if (eventName === "ResolverUpdate" && typeof args === 'object' && args !== null && 'resolver' in args && typeof args.resolver === 'string') {
            const resolverAddress = args.resolver as `0x${string}`;
            activeResolvers.add(resolverAddress);
            lastResolverBlocks.set(resolverAddress, l2Block);
          }
        });
      }
      lastL1DatastoreBlock = latestL1DatastoreBlock;
    }

    // RegistryDatastore (L2)
    const latestL2DatastoreBlock = await l2Client.getBlockNumber();
    if (latestL2DatastoreBlock > lastL2DatastoreBlock) {
      const logs = await l2Client.getLogs({
        address: l2RegistryDatastoreDeployment.address,
        fromBlock: lastL2DatastoreBlock + 1n,
        toBlock: latestL2DatastoreBlock,
      });
      if (logs.length > 0) {
        console.log("\nNew RegistryDatastore Events (L2):");
        logs.forEach(log => {
          const { eventName, args, chain, contractName, contractAddress } = formatEventLog(log, datastoreEvents, "L2", "RegistryDatastore", l2RegistryDatastoreDeployment.address);
          console.log(`- Event: ${eventName}`);
          console.log(`- Chain: ${chain} (${contractName} - ${contractAddress})`);
          console.log(`- Transaction: ${log.transactionHash}`);
          console.log(`- Block: ${log.blockNumber}`);
          console.log(`- Arguments:`, args);

          // If this is a ResolverUpdate event, add the resolver to our tracking set
          if (eventName === "ResolverUpdate" && typeof args === 'object' && args !== null && 'resolver' in args && typeof args.resolver === 'string') {
            const resolverAddress = args.resolver as `0x${string}`;
            activeResolvers.add(resolverAddress);
            lastResolverBlocks.set(resolverAddress, l2Block);
          }
        });
      }
      lastL2DatastoreBlock = latestL2DatastoreBlock;
    }

    // Check for new events from all active resolvers
    const latestL2Block = await l2Client.getBlockNumber();
    for (const resolverAddress of activeResolvers) {
      const lastBlock = lastResolverBlocks.get(resolverAddress) || l2Block;
      if (latestL2Block > lastBlock) {
        const logs = await l2Client.getLogs({
          address: resolverAddress,
          fromBlock: lastBlock + 1n,
          toBlock: latestL2Block,
        });
        if (logs.length > 0) {
          console.log(`\nNew Events for Resolver ${resolverAddress}:`);
          logs.forEach(log => {
            const { eventName, args, chain, contractName, contractAddress } = formatEventLog(log, dedicatedResolverEvents, "L2", "DedicatedResolver", resolverAddress);
            console.log(`- Event: ${eventName}`);
            console.log(`- Chain: ${chain} (${contractName} - ${contractAddress})`);
            console.log(`- Transaction: ${log.transactionHash}`);
            console.log(`- Block: ${log.blockNumber}`);
            console.log(`- Arguments:`, args);
          });
        }
        lastResolverBlocks.set(resolverAddress, latestL2Block);
      }
    }
  }, 5000);
}

listenToEvents().catch(console.error); 