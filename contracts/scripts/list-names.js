import hre from "hardhat";
import { decodeEventLog } from "viem";
import fs from "fs/promises";
import path from "path";
import dotenv from "dotenv";

// Load .env file
const ENV_FILE_PATH = path.resolve(process.cwd(), '.env');
dotenv.config({ path: ENV_FILE_PATH });

async function getOwnedNames(registry, address, parentName = '') {
  const publicClient = await hre.viem.getPublicClient();

  // First, get all NewSubname events to build the name hierarchy
  console.log("Fetching NewSubname events...");
  const newSubnameLogs = await publicClient.getLogs({
    address: registry.address,
    event: {
      type: 'event',
      name: 'NewSubname',
      inputs: [
        { type: 'uint256', name: 'labelHash', indexed: true },
        { type: 'string', name: 'label', indexed: false }
      ]
    },
    fromBlock: 0n
  });
  console.log(`Found ${newSubnameLogs.length} NewSubname events`);

  // Build a map of labelHash to label for this registry
  const labelMap = new Map();
  for (const log of newSubnameLogs) {
    try {
      const decoded = decodeEventLog({
        abi: registry.abi,
        data: log.data,
        topics: log.topics
      });
      labelMap.set(decoded.args.labelHash.toString(), decoded.args.label);
      console.log("*** labelMap set", decoded.args.labelHash.toString(), decoded.args.label);
    } catch (error) {
      console.error("Error decoding NewSubname event:", error);
    }
  }

  // Get all NameRelinquished events
  console.log("Fetching NameRelinquished events...");
  const relinquishedLogs = await publicClient.getLogs({
    address: registry.address,
    event: {
      type: 'event',
      name: 'NameRelinquished',
      inputs: [
        { type: 'uint256', name: 'tokenId', indexed: true },
        { type: 'address', name: 'sender', indexed: true }
      ]
    },
    fromBlock: 0n
  });
  console.log(`Found ${relinquishedLogs.length} NameRelinquished events`);

  const relinquishedTokenIds = new Set(relinquishedLogs.map(log => {
    try {
      const decoded = decodeEventLog({
        abi: registry.abi,
        data: log.data,
        topics: log.topics
      });
      return decoded.args.tokenId.toString();
    } catch (error) {
      console.error("Error decoding NameRelinquished event:", error);
      return null;
    }
  }).filter(Boolean));

  console.log("Relinquished token IDs:", Array.from(relinquishedTokenIds));

  // For each NewSubname, check if it's owned by the address and not relinquished
  const ownedNames = [];
  const subregistries = new Map(); // Track subregistries for recursive processing
  console.log("***** labelMap:", labelMap);
  for (const [labelHash, label] of labelMap.entries()) {
    try {
      console.log("Processing labelHash:", labelHash, "label:", label);
      
      if (relinquishedTokenIds.has(labelHash)) {
        console.log("Token was relinquished, skipping:", labelHash);
        continue;
      }
      
      let owner;
      try {
        owner = await registry.read.ownerOf([BigInt(labelHash)]);
        console.log("Current owner:", owner);
      } catch (e) {
        console.log("Error getting owner for tokenId:", labelHash, e.message);
        continue; // token may not exist anymore
      }
      
      if (owner && owner.toLowerCase() === address.toLowerCase()) {
        const fullName = parentName 
          ? `${label}.${parentName}`
          : label;
        console.log("Adding owned name:", fullName);
        ownedNames.push(fullName);

        // Check for subregistry
        try {
          const subregistry = await registry.read.getSubregistry([label]);
          if (subregistry && subregistry !== "0x0000000000000000000000000000000000000000") {
            console.log(`Found subregistry for ${label}:`, subregistry);
            subregistries.set(label, subregistry);
          }
        } catch (e) {
          console.log(`Error checking subregistry for ${label}:`, e.message);
        }
      }
    } catch (error) {
      console.error("Error processing label:", label, error);
    }
  }

  // Process subregistries recursively
  for (const [label, subregistryAddress] of subregistries) {
    const fullName = parentName ? `${label}.${parentName}` : label;
    const subregistry = await hre.viem.getContractAt("PermissionedRegistry", subregistryAddress);
    const subnames = await getOwnedNames(subregistry, address, fullName);
    ownedNames.push(...subnames);
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
  
  // Start from Root Registry - it will automatically find and process all TLDs
  const names = await getOwnedNames(RootRegistry, address);

  console.log("\nOwned names:");
  console.log("------------");
  const sortedNames = Array.from(names).sort();
  for (const name of sortedNames) {
    console.log(name);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
}); 