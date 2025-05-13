import hre from "hardhat";
import { decodeEventLog } from "viem";
import fs from "fs/promises";
import path from "path";
import dotenv from "dotenv";

// Load .env file
const ENV_FILE_PATH = path.resolve(process.cwd(), '.env');
dotenv.config({ path: ENV_FILE_PATH });

// State to track known names and their relationships
const nameState = {
  // Map of registry address -> Map of labelHash -> { label, owner, subregistry }
  registries: new Map(),
  // Map of registry address -> Set of relinquished tokenIds
  relinquished: new Map(),
  // Map of registry address -> Set of processed block numbers
  processedBlocks: new Map()
};

async function processNewSubnameEvent(registry, log) {
  const publicClient = await hre.viem.getPublicClient();
  const registryAddress = registry.address.toLowerCase();
  
  // Initialize registry state if not exists
  if (!nameState.registries.has(registryAddress)) {
    nameState.registries.set(registryAddress, new Map());
  }
  if (!nameState.relinquished.has(registryAddress)) {
    nameState.relinquished.set(registryAddress, new Set());
  }

  try {
    const decoded = decodeEventLog({
      abi: registry.abi,
      data: log.data,
      topics: log.topics
    });
  
    const labelHash = decoded.args.labelHash.toString();
    const label = decoded.args.label;
    
    
    // Update state with initial owner (from TransferSingle event that follows)
    nameState.registries.get(registryAddress).set(labelHash, {
      label,
      owner: null, // Will be set by TransferSingle event
      subregistry: null, // Will be set by SubregistryUpdate event if applicable
      isRelinquished: false
    });

  } catch (error) {
    console.error("Error processing NewSubname event:", error);
  }
}

async function processSubregistryUpdateEvent(datastore, log) {
  try {
    const decoded = decodeEventLog({
      abi: datastore.abi,
      data: log.data,
      topics: log.topics
    });
    
    const registry = decoded.args.registry.toLowerCase();
    const id = decoded.args.id.toString();
    const subregistry = decoded.args.subregistry.toLowerCase();
    const expiry = decoded.args.expiry;
    
    // Skip if expired
    if (expiry < BigInt(Math.floor(Date.now() / 1000))) {
      console.log(`Skipping expired subregistry for id ${id}`);
      return;
    }
    
    // Find the name info by id
    const registryNames = nameState.registries.get(registry);
    if (registryNames) {
      const nameInfo = registryNames.get(id);
      if (nameInfo) {
        nameInfo.subregistry = subregistry;
        console.log(`Updated subregistry for ${nameInfo.label} to ${subregistry}`);
        
        // Start watching the new subregistry
        const subregistryContract = await hre.viem.getContractAt("PermissionedRegistry", subregistry);
        await watchRegistry(subregistryContract);
      } else {
        console.log(`No name info found for id ${id} in registry ${registry}`);
      }
    } else {
      console.log(`No registry state found for ${registry}`);
    }
  } catch (error) {
    console.error("Error processing SubregistryUpdate event:", error);
  }
}

async function processTransferEvent(registry, log) {
  const registryAddress = registry.address.toLowerCase();
  
  try {
    const decoded = decodeEventLog({
      abi: registry.abi,
      data: log.data,
      topics: log.topics
    });
    
    const tokenId = decoded.args.id.toString();
    const to = decoded.args.to.toLowerCase();
    
    // Update owner in state
    const nameInfo = nameState.registries.get(registryAddress)?.get(tokenId);
    if (nameInfo) {
      nameInfo.owner = to;
      console.log(`Updated owner for ${nameInfo.label} to ${to}`);
    }
  } catch (error) {
    console.error("Error processing Transfer event:", error);
  }
}

async function processNameRelinquishedEvent(registry, log) {
  const registryAddress = registry.address.toLowerCase();
  
  try {
    const decoded = decodeEventLog({
      abi: registry.abi,
      data: log.data,
      topics: log.topics
    });
    
    const tokenId = decoded.args.tokenId.toString();
    nameState.relinquished.get(registryAddress).add(tokenId);
    
    // Update the name state
    const nameInfo = nameState.registries.get(registryAddress)?.get(tokenId);
    if (nameInfo) {
      nameInfo.isRelinquished = true;
    }
  } catch (error) {
    console.error("Error processing NameRelinquished event:", error);
  }
}

async function watchRegistry(registry) {
  const publicClient = await hre.viem.getPublicClient();
  const registryAddress = registry.address.toLowerCase();
  
  // Initialize registry state if not exists
  if (!nameState.registries.has(registryAddress)) {
    nameState.registries.set(registryAddress, new Map());
  }
  if (!nameState.relinquished.has(registryAddress)) {
    nameState.relinquished.set(registryAddress, new Set());
  }
  if (!nameState.processedBlocks.has(registryAddress)) {
    nameState.processedBlocks.set(registryAddress, 0n);
  }

  // Get the last processed block
  const fromBlock = nameState.processedBlocks.get(registryAddress);

  // Watch for new events
  const newSubnameLogs = await publicClient.getLogs({
    address: registryAddress,
    event: {
      type: 'event',
      name: 'NewSubname',
      inputs: [
        { type: 'uint256', name: 'labelHash', indexed: true },
        { type: 'string', name: 'label', indexed: false }
      ]
    },
    fromBlock
  });

  const transferLogs = await publicClient.getLogs({
    address: registryAddress,
    event: {
      type: 'event',
      name: 'TransferSingle',
      inputs: [
        { type: 'address', name: 'operator', indexed: true },
        { type: 'address', name: 'from', indexed: true },
        { type: 'address', name: 'to', indexed: true },
        { type: 'uint256', name: 'id', indexed: false },
        { type: 'uint256', name: 'value', indexed: false }
      ]
    },
    fromBlock
  });

  const relinquishedLogs = await publicClient.getLogs({
    address: registryAddress,
    event: {
      type: 'event',
      name: 'NameRelinquished',
      inputs: [
        { type: 'uint256', name: 'tokenId', indexed: true },
        { type: 'address', name: 'sender', indexed: true }
      ]
    },
    fromBlock
  });

  // Process new events
  for (const log of newSubnameLogs) {
    await processNewSubnameEvent(registry, log);
  }

  for (const log of transferLogs) {
    await processTransferEvent(registry, log);
  }

  for (const log of relinquishedLogs) {
    await processNameRelinquishedEvent(registry, log);
  }

  // Update processed block
  const currentBlock = await publicClient.getBlockNumber();
  nameState.processedBlocks.set(registryAddress, currentBlock);
}

async function watchDatastore(datastore) {
  const publicClient = await hre.viem.getPublicClient();
  const datastoreAddress = datastore.address;
  
  // Get the last processed block
  const fromBlock = 0n; // Start from the beginning for datastore events

  // Watch for SubregistryUpdate events
  const subregistryUpdateLogs = await publicClient.getLogs({
    address: datastoreAddress,
    event: {
      type: 'event',
      name: 'SubregistryUpdate',
      inputs: [
        { type: 'address', name: 'registry', indexed: true },
        { type: 'uint256', name: 'id', indexed: true },
        { type: 'address', name: 'subregistry', indexed: false },
        { type: 'uint64', name: 'expiry', indexed: false },
        { type: 'uint32', name: 'data', indexed: false }
      ]
    },
    fromBlock
  });

  // Process SubregistryUpdate events
  for (const log of subregistryUpdateLogs) {
    await processSubregistryUpdateEvent(datastore, log);
  }
}

function getOwnedNames(registry, address, parentName = '') {
  const registryAddress = registry.address.toLowerCase();
  const ownedNames = [];
  const registryNames = nameState.registries.get(registryAddress);
  const relinquished = nameState.relinquished.get(registryAddress);

  if (!registryNames) {
    console.log(`No registry names found for ${registryAddress}`);
    return ownedNames;
  }

  console.log(`\nChecking registry ${registryAddress} for names owned by ${address}`);
  console.log(`Found ${registryNames.size} names in registry`);

  // First check direct ownership in this registry
  for (const [labelHash, info] of registryNames) {
    if (relinquished.has(labelHash) || info.isRelinquished) {
      console.log(`Skipping relinquished name: ${info.label}`);
      continue;
    }
    
    if (info.owner && info.owner.toLowerCase() === address.toLowerCase()) {
      const fullName = parentName ? `${info.label}.${parentName}` : info.label;
      console.log(`Found owned name: ${fullName}`);
      ownedNames.push(fullName);
    } else {
      console.log(`Name ${info.label} owned by ${info.owner}, not ${address}`);
    }
  }

  // Then check all subregistries recursively
  for (const [labelHash, info] of registryNames) {
    if (info.subregistry && info.subregistry !== '0x0000000000000000000000000000000000000000') {
      const fullName = parentName ? `${info.label}.${parentName}` : info.label;
      console.log(`Checking subregistry ${info.subregistry} for ${fullName}`);
      const subnames = getOwnedNames({ address: info.subregistry }, address, fullName);
      console.log(`Found ${subnames.length} subnames for ${fullName}`);
      ownedNames.push(...subnames);
    }
  }

  return ownedNames;
}

async function main() {
  // Get the address from command line argument or environment
  const address = process.argv[2] || process.env.DEPLOYER_ADDRESS;
  
  if (!address) {
    console.error("Please provide an address as argument or set DEPLOYER_ADDRESS in .env");
    process.exit(1);
  }

  console.log(`Querying names owned by ${address}...`);

  // Load the Root registry contract
  const rootRegistryAddress = process.env.ROOT_REGISTRY_ADDRESS;
  console.log("ROOT_REGISTRY_ADDRESS:", rootRegistryAddress);
  if (!rootRegistryAddress) {
    console.error("ROOT_REGISTRY_ADDRESS not found in .env");
    process.exit(1);
  }

  // Get the datastore address from env
  const datastoreAddress = process.env.REGISTRY_DATASTORE_ADDRESS;
  if (!datastoreAddress) {
    console.error("REGISTRY_DATASTORE_ADDRESS not found in .env");
    process.exit(1);
  }

  // Get the Root registry contract
  const RootRegistry = await hre.viem.getContractAt("PermissionedRegistry", rootRegistryAddress);
  
  // Get the datastore contract
  const Datastore = await hre.viem.getContractAt("RegistryDatastore", datastoreAddress);
  
  // First, watch all registries for NewSubname events
  await watchRegistry(RootRegistry);
  
  // Then, watch the datastore for SubregistryUpdate events
  await watchDatastore(Datastore);

  // Get owned names from state
  const names = getOwnedNames(RootRegistry, address);

  console.log("\nOwned names:");
  console.log("------------");
  const sortedNames = Array.from(names).sort();
  for (const name of sortedNames) {
    console.log(name);
  }

  // Debug output
  console.log("\nRegistry State:");
  console.log("--------------");
  for (const [registryAddr, names] of nameState.registries) {
    console.log(`\nRegistry ${registryAddr}:`);
    for (const [labelHash, info] of names) {
      console.log(`  ${info.label}:`);
      console.log(`    Owner: ${info.owner}`);
      console.log(`    Subregistry: ${info.subregistry}`);
      console.log(`    Relinquished: ${info.isRelinquished}`);
    }
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
}); 