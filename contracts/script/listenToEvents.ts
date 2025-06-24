import { createPublicClient, http, type Chain, getContract, type Log, decodeEventLog, type Abi, type DecodeEventLogReturnType } from "viem";
import { readFileSync } from "fs";
import { join } from "path";
import { deployments, eventABIs, resolverEvents } from "./shared/config.js";

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

const otherl2Chain: Chain = {
  id: 31339,
  name: "Other L2",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: {
    default: { http: ["http://127.0.0.1:8547"] },
    public: { http: ["http://127.0.0.1:8547"] },
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

const otherl2Client = createPublicClient({
  chain: otherl2Chain,
  transport: http(),
});

// Get the datastore address from RootRegistry
const rootRegistryABI = deployments.rootRegistry.abi;

function decodeEvent(log: Log, events: Abi): DecodeEventLogReturnType | null {
  try {
    return decodeEventLog({
      abi: events,
      data: log.data,
      topics: log.topics,
    });
  } catch (error) {
    return null;
  }
}

function formatEventLog(log: Log, events: Abi, chain: string, contractName: string, contractAddress: string) {
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
const l1ActiveResolvers = new Set<`0x${string}`>();
const l2ActiveResolvers = new Set<`0x${string}`>();

async function listenToEvents() {
  console.log("Starting to listen to registry and resolver events...\n");
  
  // Display contract addresses
  console.log("Contract Addresses:");
  console.log("-------------------");
  console.log(`RootRegistry: ${deployments.rootRegistry.address}`);
  console.log(`L1ETHRegistry: ${deployments.l1EthRegistry.address}`);
  console.log(`ETHRegistry: ${deployments.ethRegistry.address}`);
  console.log(`L1 RegistryDatastore: ${deployments.l1RegistryDatastore.address}`);
  console.log(`L2 RegistryDatastore: ${deployments.l2RegistryDatastore.address}`);
  console.log(`DedicatedResolverImpl: ${deployments.dedicatedResolverImpl.address}`);
  console.log(`L1EjectionController: ${deployments.l1EjectionController.address}`);
  console.log(`L2EjectionController: ${deployments.l2EjectionController.address}`);
  console.log(`MockDurinL2Registry: ${deployments.mockDurinL2Registry.address}`);
  console.log(`MockDurinL1ResolverImpl: ${deployments.mockDurinL1ResolverImpl.address}`);

  // Get the datastore address from RootRegistry
  const rootRegistry = getContract({
    address: deployments.rootRegistry.address,
    abi: rootRegistryABI,
    client: l1Client,
  });

  const rootRegistryDatastore = await rootRegistry.read.datastore();
  console.log(`RootRegistry's Datastore: ${rootRegistryDatastore}`);
  console.log("-------------------\n");

  // Get current block numbers
  const l1Block = await l1Client.getBlockNumber();
  const l2Block = await l2Client.getBlockNumber();
  const otherl2Block = await otherl2Client.getBlockNumber();
  console.log(`Current L1 Block: ${l1Block}`);
  console.log(`Current L2 Block: ${l2Block}`);
  console.log(`Current Other L2 Block: ${otherl2Block}\n`);

  // Fetch historical events
  console.log("Fetching historical events...\n");

  // RootRegistry historical events
  const rootRegistryLogs = await l1Client.getLogs({
    address: deployments.rootRegistry.address,
    fromBlock: 0n,
    toBlock: l1Block,
  });
  if (rootRegistryLogs.length > 0) {
    console.log("\n *** Historical RootRegistry Events:");
    rootRegistryLogs.forEach(log => {
      const { eventName, args, chain, contractName, contractAddress } = formatEventLog(log, eventABIs.registryEvents, "L1", "RootRegistry", deployments.rootRegistry.address);
      console.log(`- Event: ${eventName}`);
      console.log(`- Chain: ${chain} (${contractName} - ${contractAddress})`);
      console.log(`- Transaction: ${log.transactionHash}`);
      console.log(`- Block: ${log.blockNumber}`);
      console.log(`- Arguments:`, args);
    });
  }

  // L1ETHRegistry historical events
  const l1EthRegistryLogs = await l1Client.getLogs({
    address: deployments.l1EthRegistry.address,
    fromBlock: 0n,
    toBlock: l1Block,
  });
  if (l1EthRegistryLogs.length > 0) {
    console.log("\n *** Historical L1ETHRegistry Events:");
    l1EthRegistryLogs.forEach(log => {
      const { eventName, args, chain, contractName, contractAddress } = formatEventLog(log, eventABIs.registryEvents, "L1", "L1ETHRegistry", deployments.l1EthRegistry.address);
      console.log(`- Event: ${eventName}`);
      console.log(`- Chain: ${chain} (${contractName} - ${contractAddress})`);
      console.log(`- Transaction: ${log.transactionHash}`);
      console.log(`- Block: ${log.blockNumber}`);
      console.log(`- Arguments:`, args);

      // Track NameRelinquished events
      if (eventName === "NameRelinquished") {
        console.log("✓ NameRelinquished event detected");
        console.log(`  Token ID: ${args.tokenId}`);
        console.log(`  Relinquished by: ${args.relinquishedBy}`);
      }
      if(eventName === "ResolverUpdate"){
        console.log("✓ ResolverUpdate event detected");
        console.log(`  Resolver: ${args.resolver}`);
        l1ActiveResolvers.add(args.resolver as `0x${string}`);
      }
    });
  }

  // ETHRegistry historical events
  const ethRegistryLogs = await l2Client.getLogs({
    address: deployments.ethRegistry.address,
    fromBlock: 0n,
    toBlock: l2Block,
  });
  if (ethRegistryLogs.length > 0) {
    console.log("\n *** Historical ETHRegistry Events:");
    ethRegistryLogs.forEach(log => {
      const { eventName, args, chain, contractName, contractAddress } = formatEventLog(log, eventABIs.registryEvents, "L2", "ETHRegistry", deployments.ethRegistry.address);
      console.log(`- Event: ${eventName}`);
      console.log(`- Chain: ${chain} (${contractName} - ${contractAddress})`);
      console.log(`- Transaction: ${log.transactionHash}`);
      console.log(`- Block: ${log.blockNumber}`);
      console.log(`- Arguments:`, args);

      // Track NameRelinquished events
      if (eventName === "NameRelinquished") {
        console.log("✓ NameRelinquished event detected");
        console.log(`  Token ID: ${args.tokenId}`);
        console.log(`  Relinquished by: ${args.relinquishedBy}`);
      }
    });
  }

  for (const resolverAddress of l1ActiveResolvers) {
    const resolverLogs = await l1Client.getLogs({
      address: resolverAddress,
      fromBlock: 0n,
      toBlock: l1Block,
    });
    console.log(`\n *** Historical Events for L1 Resolver ${resolverAddress}:`);
    if (resolverLogs.length > 0) {
      resolverLogs.forEach(log => {
        const { eventName, args, chain, contractName, contractAddress } = formatEventLog(log, resolverEvents, "L1", "DedicatedResolver", resolverAddress);
        console.log(`- Event: ${eventName}`);
        console.log(`- Chain: ${chain} (${contractName} - ${contractAddress})`);
        console.log(`- Transaction: ${log.transactionHash}`);
        console.log(`- Block: ${log.blockNumber}`);
        console.log(`- Arguments:`, args);
      });
    }else{
      console.log(`No historical events found for Resolver ${resolverAddress}`);
    }
  } 

  // Fetch historical events for all active resolvers
  for (const resolverAddress of l2ActiveResolvers) {
    const resolverLogs = await l2Client.getLogs({
      address: resolverAddress,
      fromBlock: 0n,
      toBlock: l2Block,
    });
    console.log(`\n *** Historical Events for L2 Resolver ${resolverAddress}:`);
    if (resolverLogs.length > 0) {
      resolverLogs.forEach(log => {
        const { eventName, args, chain, contractName, contractAddress } = formatEventLog(log, resolverEvents, "L2", "DedicatedResolver", resolverAddress);
        console.log(`- Event: ${eventName}`);
        console.log(`- Chain: ${chain} (${contractName} - ${contractAddress})`);
        console.log(`- Transaction: ${log.transactionHash}`);
        console.log(`- Block: ${log.blockNumber}`);
        console.log(`- Arguments:`, args);
      });
    }else{
      console.log(`No historical events found for Resolver ${resolverAddress}`);
    }
  }

  // L1EjectionController historical events
  const l1EjectionControllerLogs = await l1Client.getLogs({
    address: deployments.l1EjectionController.address,
    fromBlock: 0n,
    toBlock: l1Block,
  });
  if (l1EjectionControllerLogs.length > 0) {
    console.log(`\n *** Historical L1EjectionController Events: ${l1EjectionControllerLogs.length}`);
    l1EjectionControllerLogs.forEach(log => {
      const { eventName, args, chain, contractName, contractAddress } = formatEventLog(log, eventABIs.ejectionControllerEvents, "L1", "L1EjectionController", deployments.l1EjectionController.address);
      console.log(`- Event: ${eventName}`);
      console.log(`- Chain: ${chain} (${contractName} - ${contractAddress})`);
      console.log(`- Transaction: ${log.transactionHash}`);
      console.log(`- Block: ${log.blockNumber}`);
      console.log(`- Arguments:`, args);
    });
  }

  // L2EjectionController historical events
  const l2EjectionControllerLogs = await l2Client.getLogs({
    address: deployments.l2EjectionController.address,
    fromBlock: 0n,
    toBlock: l2Block,
  });
  if (l2EjectionControllerLogs.length > 0) {
    console.log(`\n *** Historical L2EjectionController Events: ${l2EjectionControllerLogs.length}`);
    l2EjectionControllerLogs.forEach(log => {
      const { eventName, args, chain, contractName, contractAddress } = formatEventLog(log, eventABIs.ejectionControllerEvents, "L2", "L2EjectionController", deployments.l2EjectionController.address);
      console.log(`- Event: ${eventName}`);
      console.log(`- Chain: ${chain} (${contractName} - ${contractAddress})`);
      console.log(`- Transaction: ${log.transactionHash}`);
      console.log(`- Block: ${log.blockNumber}`);
      console.log(`- Arguments:`, args);
    });
  }

  // MockDurinL2Registry historical events
  const mockDurinL2RegistryLogs = await otherl2Client.getLogs({
    address: deployments.mockDurinL2Registry.address,
    fromBlock: 0n,
    toBlock: otherl2Block,
  });
  if (mockDurinL2RegistryLogs.length > 0) {
    console.log(`\n *** Historical MockDurinL2Registry Events: ${mockDurinL2RegistryLogs.length}`);
    mockDurinL2RegistryLogs.forEach(log => {
      const { eventName, args, chain, contractName, contractAddress } = formatEventLog(log, eventABIs.mockDurinL2RegistryEvents, "Other L2", "MockDurinL2Registry", deployments.mockDurinL2Registry.address);
      console.log(`- Event: ${eventName}`);
      console.log(`- Chain: ${chain} (${contractName} - ${contractAddress})`);
      console.log(`- Transaction: ${log.transactionHash}`);
      console.log(`- Block: ${log.blockNumber}`);
      console.log(`- Arguments:`, args);
    });
  }

  console.log("\nNow listening for new events...\n");

  // Start listening for new events
  let lastRootRegistryBlock = l1Block;
  let lastL1EthRegistryBlock = l1Block;
  let lastEthRegistryBlock = l2Block;
  let lastL1DatastoreBlock = l1Block;
  let lastMockDurinL2RegistryBlock = otherl2Block;
  const lastResolverBlocks = new Map<`0x${string}`, bigint>();

  // Initialize last block for each active resolver
  for (const resolverAddress of l1ActiveResolvers) {
    lastResolverBlocks.set(resolverAddress, l1Block);
  }
  for (const resolverAddress of l2ActiveResolvers) {
    lastResolverBlocks.set(resolverAddress, l2Block);
  }
  

  setInterval(async () => {
    const activeResolvers = new Set<`0x${string}`>();
    // RootRegistry
    const latestRootRegistryBlock = await l1Client.getBlockNumber();
    if (latestRootRegistryBlock > lastRootRegistryBlock) {
      const logs = await l1Client.getLogs({
        address: deployments.rootRegistry.address,
        fromBlock: lastRootRegistryBlock + 1n,
        toBlock: latestRootRegistryBlock,
      });
      if (logs.length > 0) {
        console.log("\nNew RootRegistry Events:");
        logs.forEach(log => {
          const { eventName, args, chain, contractName, contractAddress } = formatEventLog(log, eventABIs.registryEvents, "L1", "RootRegistry", deployments.rootRegistry.address);
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
        address: deployments.l1EthRegistry.address,
        fromBlock: lastL1EthRegistryBlock + 1n,
        toBlock: latestL1EthRegistryBlock,
      });
      if (logs.length > 0) {
        console.log("\nNew L1ETHRegistry Events:");
        logs.forEach(log => {
          const { eventName, args, chain, contractName, contractAddress } = formatEventLog(log, eventABIs.registryEvents, "L1", "L1ETHRegistry", deployments.l1EthRegistry.address);
          console.log(`- Event: ${eventName}`);
          console.log(`- Chain: ${chain} (${contractName} - ${contractAddress})`);
          console.log(`- Transaction: ${log.transactionHash}`);
          console.log(`- Block: ${log.blockNumber}`);
          console.log(`- Arguments:`, args);

          // Track NameRelinquished events
          if (eventName === "NameRelinquished") {
            console.log("✓ NameRelinquished event detected");
            console.log(`  Token ID: ${args.tokenId}`);
            console.log(`  Relinquished by: ${args.relinquishedBy}`);
          }
        });
      }
      lastL1EthRegistryBlock = latestL1EthRegistryBlock;
    }

    // ETHRegistry (L2)
    const latestEthRegistryBlock = await l2Client.getBlockNumber();
    if (latestEthRegistryBlock > lastEthRegistryBlock) {
      const logs = await l2Client.getLogs({
        address: deployments.ethRegistry.address,
        fromBlock: lastEthRegistryBlock + 1n,
        toBlock: latestEthRegistryBlock,
      });
      if (logs.length > 0) {
        console.log("\nNew ETHRegistry Events:");
        logs.forEach(log => {
          const { eventName, args, chain, contractName, contractAddress } = formatEventLog(log, eventABIs.registryEvents, "L2", "ETHRegistry", deployments.ethRegistry.address);
          console.log(`- Event: ${eventName}`);
          console.log(`- Chain: ${chain} (${contractName} - ${contractAddress})`);
          console.log(`- Transaction: ${log.transactionHash}`);
          console.log(`- Block: ${log.blockNumber}`);
          console.log(`- Arguments:`, args);

          // Track NameRelinquished events
          if (eventName === "NameRelinquished") {
            console.log("✓ NameRelinquished event detected");
            console.log(`  Token ID: ${args.tokenId}`);
            console.log(`  Relinquished by: ${args.relinquishedBy}`);
          }
        });
      }
      lastEthRegistryBlock = latestEthRegistryBlock;
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
            const { eventName, args, chain, contractName, contractAddress } = formatEventLog(log, resolverEvents, "L2", "DedicatedResolver", resolverAddress);
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

    // MockDurinL2Registry (Other L2)
    const latestOtherl2Block = await otherl2Client.getBlockNumber();
    if (latestOtherl2Block > lastMockDurinL2RegistryBlock) {
      const logs = await otherl2Client.getLogs({
        address: deployments.mockDurinL2Registry.address,
        fromBlock: lastMockDurinL2RegistryBlock + 1n,
        toBlock: latestOtherl2Block,
      });
      if (logs.length > 0) {
        console.log("\nNew MockDurinL2Registry Events:");
        logs.forEach(log => {
          const { eventName, args, chain, contractName, contractAddress } = formatEventLog(log, eventABIs.mockDurinL2RegistryEvents, "Other L2", "MockDurinL2Registry", deployments.mockDurinL2Registry.address);
          console.log(`- Event: ${eventName}`);
          console.log(`- Chain: ${chain} (${contractName} - ${contractAddress})`);
          console.log(`- Transaction: ${log.transactionHash}`);
          console.log(`- Block: ${log.blockNumber}`);
          console.log(`- Arguments:`, args);
        });
      }
      lastMockDurinL2RegistryBlock = latestOtherl2Block;
    }
  }, 5000);
}

listenToEvents().catch(console.error);