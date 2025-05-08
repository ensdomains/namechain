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

async function processNewSubnameEvent(registry, log, address) {
  const publicClient = await hre.viem.getPublicClient();
  const registryAddress = registry.address;
  
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
    console.log("***** decoded:", {registryAddress, log, decoded});
    const labelHash = decoded.args.labelHash.toString();
    const label = decoded.args.label;
    
    console.log("Processing NewSubname event:", { labelHash, label });
    
    // Check ownership
    let owner;
    try {
      owner = await registry.read.ownerOf([BigInt(labelHash)]);
    } catch (e) {
      console.log("Error getting owner for tokenId:", labelHash, e.message);
      return;
    }

    // Check for subregistry
    let subregistry = null;
    try {
      subregistry = await registry.read.getSubregistry([label]);
      if (subregistry === "0x0000000000000000000000000000000000000000") {
        subregistry = null;
      }
    } catch (e) {
      console.log(`Error checking subregistry for ${label}:`, e.message);
    }

    // Update state
    nameState.registries.get(registryAddress).set(labelHash, {
      label,
      owner,
      subregistry,
      isRelinquished: false
    });

    // If this is a new subregistry, start watching it
    if (subregistry) {
      const subregistryContract = await hre.viem.getContractAt("PermissionedRegistry", subregistry);
      await watchRegistry(subregistryContract, address);
    }

  } catch (error) {
    console.error("Error processing NewSubname event:", error);
  }
}

async function processNameRelinquishedEvent(registry, log) {
  const registryAddress = registry.address;
  
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

async function watchRegistry(registry, address) {
  const publicClient = await hre.viem.getPublicClient();
  const registryAddress = registry.address;
  
  // Initialize state for this registry
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
    await processNewSubnameEvent(registry, log, address);
  }

  for (const log of relinquishedLogs) {
    await processNameRelinquishedEvent(registry, log);
  }

  // Update processed block
  const currentBlock = await publicClient.getBlockNumber();
  nameState.processedBlocks.set(registryAddress, currentBlock);
}

function getOwnedNames(registry, address, parentName = '') {
  const registryAddress = registry.address;
  const ownedNames = [];
  const registryNames = nameState.registries.get(registryAddress);
  const relinquished = nameState.relinquished.get(registryAddress);

  if (!registryNames) return ownedNames;

  for (const [labelHash, info] of registryNames) {
    if (relinquished.has(labelHash) || info.isRelinquished) continue;
    
    if (info.owner.toLowerCase() === address.toLowerCase()) {
      const fullName = parentName ? `${info.label}.${parentName}` : info.label;
      ownedNames.push(fullName);

      // Check for subregistry
      if (info.subregistry) {
        const subregistry = nameState.registries.get(info.subregistry);
        if (subregistry) {
          const subnames = getOwnedNames({ address: info.subregistry }, address, fullName);
          ownedNames.push(...subnames);
        }
      }
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

  // Get the Root registry contract
  const RootRegistry = await hre.viem.getContractAt("PermissionedRegistry", rootRegistryAddress);
  
  // Start watching the Root Registry
  await watchRegistry(RootRegistry, address);

  // Get owned names from state
  const names = getOwnedNames(RootRegistry, address);

  console.log("\nOwned names:");
  console.log("------------");
  const sortedNames = Array.from(names).sort();
  for (const name of sortedNames) {
    console.log(name);
  }
  console.log("***** nameState.registries:", nameState.registries);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
}); 