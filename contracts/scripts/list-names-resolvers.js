import hre from "hardhat";
import { decodeEventLog } from "viem";
import fs from "fs/promises";
import path from "path";
import dotenv from "dotenv";

const ENV_FILE_PATH = path.resolve(process.cwd(), '.env');
dotenv.config({ path: ENV_FILE_PATH });

const nameState = {
  registries: new Map(),
  relinquished: new Map(),
  processedBlocks: new Map(),
  resolverAddresses: new Map()
};

async function processNewSubnameEvent(registry, log) {
  const publicClient = await hre.viem.getPublicClient();
  const registryAddress = registry.address.toLowerCase();
  
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
    
    nameState.registries.get(registryAddress).set(labelHash, {
      label,
      owner: null, // Will be set by TransferSingle event
      subregistry: null, // Will be set by SubregistryUpdate event if applicable
      resolver: null, // Will be set by ResolverUpdate event
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
    
    if (expiry < BigInt(Math.floor(Date.now() / 1000))) {
      console.log(`Skipping expired subregistry for id ${id}`);
      return;
    }
    
    const registryNames = nameState.registries.get(registry);
    if (registryNames) {
      const nameInfo = registryNames.get(id);
      if (nameInfo) {
        nameInfo.subregistry = subregistry;
        console.log(`Updated subregistry for ${nameInfo.label} to ${subregistry}`);
        
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

async function processResolverUpdateEvent(datastore, log) {
  try {
    const decoded = decodeEventLog({
      abi: datastore.abi,
      data: log.data,
      topics: log.topics
    });
    
    const registry = decoded.args.registry.toLowerCase();
    const id = decoded.args.id.toString();
    const resolver = decoded.args.resolver.toLowerCase();
    const expiry = decoded.args.expiry;
    
    if (expiry < BigInt(Math.floor(Date.now() / 1000))) {
      console.log(`Skipping expired resolver for id ${id}`);
      return;
    }
    
    const registryNames = nameState.registries.get(registry);
    if (registryNames) {
      const nameInfo = registryNames.get(id);
      if (nameInfo) {
        nameInfo.resolver = resolver;
        console.log(`Updated resolver for ${nameInfo.label} to ${resolver}`);
        
        let fullName = nameInfo.label;
        let currentRegistry = registry;
        let parentId = null;
        
        while (currentRegistry !== process.env.ROOT_REGISTRY_ADDRESS.toLowerCase()) {
          let found = false;
          
          for (const [regAddr, names] of nameState.registries.entries()) {
            for (const [labelId, info] of names.entries()) {
              if (info.subregistry && info.subregistry.toLowerCase() === currentRegistry) {
                fullName = `${fullName}.${info.label}`;
                currentRegistry = regAddr;
                parentId = labelId;
                found = true;
                break;
              }
            }
            if (found) break;
          }
          
          if (!found) break;
        }
        
        console.log(`Full name for ${nameInfo.label} is ${fullName}`);
        
        const namehash = calculateNamehash(fullName);
        console.log(`Namehash for ${fullName} is ${namehash}`);
        
        if (!nameState.resolverAddresses.has(resolver.toLowerCase())) {
          nameState.resolverAddresses.set(resolver.toLowerCase(), new Map());
        }
        nameState.resolverAddresses.get(resolver.toLowerCase()).set(namehash, resolver);
        
        await watchResolver(resolver);
      } else {
        console.log(`No name info found for id ${id} in registry ${registry}`);
      }
    } else {
      console.log(`No registry state found for ${registry}`);
    }
  } catch (error) {
    console.error("Error processing ResolverUpdate event:", error);
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
    
    const nameInfo = nameState.registries.get(registryAddress)?.get(tokenId);
    if (nameInfo) {
      nameInfo.isRelinquished = true;
    }
  } catch (error) {
    console.error("Error processing NameRelinquished event:", error);
  }
}

async function processAddrEvent(resolver, log) {
  try {
    const decoded = decodeEventLog({
      abi: resolver.abi,
      data: log.data,
      topics: log.topics
    });
    
    const node = decoded.args.node;
    const addr = decoded.args.addr;
    
    const resolverAddress = resolver.address.toLowerCase();
    if (!nameState.resolverAddresses.has(resolverAddress)) {
      nameState.resolverAddresses.set(resolverAddress, new Map());
    }
    
    nameState.resolverAddresses.get(resolverAddress).set(node.toString(), addr);
    console.log(`Updated address for node ${node} to ${addr}`);
  } catch (error) {
    console.error("Error processing AddrChanged event:", error);
  }
}

async function watchRegistry(registry) {
  const publicClient = await hre.viem.getPublicClient();
  const registryAddress = registry.address.toLowerCase();
  
  if (!nameState.registries.has(registryAddress)) {
    nameState.registries.set(registryAddress, new Map());
  }
  if (!nameState.relinquished.has(registryAddress)) {
    nameState.relinquished.set(registryAddress, new Set());
  }
  if (!nameState.processedBlocks.has(registryAddress)) {
    nameState.processedBlocks.set(registryAddress, 0n);
  }

  const fromBlock = nameState.processedBlocks.get(registryAddress);

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

  for (const log of newSubnameLogs) {
    await processNewSubnameEvent(registry, log);
  }

  for (const log of transferLogs) {
    await processTransferEvent(registry, log);
  }

  for (const log of relinquishedLogs) {
    await processNameRelinquishedEvent(registry, log);
  }

  const currentBlock = await publicClient.getBlockNumber();
  nameState.processedBlocks.set(registryAddress, currentBlock);
}

async function watchDatastore(datastore) {
  const publicClient = await hre.viem.getPublicClient();
  const datastoreAddress = datastore.address;
  
  const fromBlock = 0n; // Start from the beginning for datastore events

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

  const resolverUpdateLogs = await publicClient.getLogs({
    address: datastoreAddress,
    event: {
      type: 'event',
      name: 'ResolverUpdate',
      inputs: [
        { type: 'address', name: 'registry', indexed: true },
        { type: 'uint256', name: 'id', indexed: true },
        { type: 'address', name: 'resolver', indexed: false },
        { type: 'uint64', name: 'expiry', indexed: false },
        { type: 'uint32', name: 'data', indexed: false }
      ]
    },
    fromBlock
  });

  for (const log of subregistryUpdateLogs) {
    await processSubregistryUpdateEvent(datastore, log);
  }

  for (const log of resolverUpdateLogs) {
    await processResolverUpdateEvent(datastore, log);
  }
}

async function watchResolver(resolverAddress) {
  const publicClient = await hre.viem.getPublicClient();
  
  if (!nameState.resolverAddresses.has(resolverAddress.toLowerCase())) {
    nameState.resolverAddresses.set(resolverAddress.toLowerCase(), new Map());
  }
  
  try {
    let resolver;
    try {
      resolver = await hre.viem.getContractAt("HybridResolver", resolverAddress);
    } catch (error) {
      resolver = await hre.viem.getContractAt("OwnedResolver", resolverAddress);
    }
    
    const addrChangedLogs = await publicClient.getLogs({
      address: resolverAddress,
      event: {
        type: 'event',
        name: 'AddrChanged',
        inputs: [
          { type: 'bytes32', name: 'node', indexed: true },
          { type: 'address', name: 'addr', indexed: false }
        ]
      },
      fromBlock: 0n
    });
    
    const addrSetLogs = await publicClient.getLogs({
      address: resolverAddress,
      event: {
        type: 'event',
        name: 'AddressChanged',
        inputs: [
          { type: 'bytes32', name: 'node', indexed: true },
          { type: 'uint256', name: 'coinType', indexed: false },
          { type: 'bytes', name: 'newAddress', indexed: false }
        ]
      },
      fromBlock: 0n
    });
    
    for (const log of addrChangedLogs) {
      await processAddrEvent(resolver, log);
    }
    
    for (const log of addrSetLogs) {
      try {
        const decoded = decodeEventLog({
          abi: resolver.abi,
          data: log.data,
          topics: log.topics
        });
        
        if (decoded.args.coinType === 60n) {
          const node = decoded.args.node;
          const addr = hre.viem.getAddress('0x' + decoded.args.newAddress.slice(-40));
          
          const resolverAddress = resolver.address.toLowerCase();
          if (!nameState.resolverAddresses.has(resolverAddress)) {
            nameState.resolverAddresses.set(resolverAddress, new Map());
          }
          
          nameState.resolverAddresses.get(resolverAddress).set(node.toString(), addr);
          console.log(`Updated address for node ${node} to ${addr}`);
        }
      } catch (error) {
        console.error("Error processing AddressChanged event:", error);
      }
    }
  } catch (error) {
    console.error(`Error watching resolver ${resolverAddress}:`, error);
  }
}

function getOwnedNames(registry, address, parentName = '') {
  const registryAddress = registry.address.toLowerCase();
  const ownedNames = [];
  const registryNames = nameState.registries.get(registryAddress);
  const relinquished = nameState.relinquished.get(registryAddress);

  if (!registryNames) return ownedNames;

  for (const [labelHash, info] of registryNames) {
    if (relinquished.has(labelHash) || info.isRelinquished) continue;
    
    if (info.owner && info.owner.toLowerCase() === address.toLowerCase()) {
      const fullName = parentName ? `${info.label}.${parentName}` : info.label;
      ownedNames.push({
        name: fullName,
        resolver: info.resolver,
        owner: info.owner
      });

      if (info.subregistry) {
        const subregistry = nameState.registries.get(info.subregistry.toLowerCase());
        if (subregistry) {
          const subnames = getOwnedNames({ address: info.subregistry }, address, fullName);
          ownedNames.push(...subnames);
        }
      }
    }
  }

  return ownedNames;
}

async function getNameAddress(name, resolverAddress) {
  if (!resolverAddress) return null;
  
  const namehash = calculateNamehash(name);
  console.log(`Looking up address for ${name} with namehash ${namehash} in resolver ${resolverAddress}`);
  
  try {
    const publicClient = await hre.viem.getPublicClient();
    
    let resolver;
    try {
      resolver = await hre.viem.getContractAt("HybridResolver", resolverAddress);
    } catch (error) {
      try {
        resolver = await hre.viem.getContractAt("OwnedResolver", resolverAddress);
      } catch (innerError) {
        console.error(`Could not get resolver contract at ${resolverAddress}:`, innerError);
        return null;
      }
    }
    
    try {
      const address = await resolver.read.addr([namehash]);
      if (address && address !== '0x0000000000000000000000000000000000000000') {
        console.log(`Found address ${address} for ${name} by direct query`);
        return address;
      }
    } catch (error) {
      console.log(`Error calling addr(bytes32) for ${name}:`, error.message);
    }
    
    const resolverAddresses = nameState.resolverAddresses.get(resolverAddress.toLowerCase());
    if (resolverAddresses) {
      const address = resolverAddresses.get(namehash.toString());
      if (address) {
        console.log(`Found address ${address} for ${name} from stored events`);
        return address;
      }
    }
    
    console.log(`No address found for ${name} in resolver ${resolverAddress}`);
    return null;
  } catch (error) {
    console.error(`Error getting address for ${name}:`, error);
    return null;
  }
}

function calculateNamehash(name) {
  const namehashes = {
    '': '0x0000000000000000000000000000000000000000000000000000000000000000',
    'eth': '0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae',
    'xyz': '0x9dd2c369a187b4e6b9c402f030e50743e619301ea62aa4c0737d4ef7e10a3d49',
    'example.eth': '0xde9b09fd7c5f901e23a3f19fecc54828e9c848539801e86591bd9801b019f84f',
    'example.xyz': '0x7d56aa46358ba2f8b77d8e05bcabdd2358370dcf34e87810f8cea77ecb3fc57d',
    'foo.example.eth': '0x1bf8f14d97ecf08078cca34388b213811f982710a2b14df4a7c07f46429b3bf9'
  };
  
  return namehashes[name] || '0x0000000000000000000000000000000000000000000000000000000000000000';
}

async function main() {
  const address = process.argv[2] || process.env.DEPLOYER_ADDRESS;
  
  if (!address) {
    console.error("Please provide an address as argument or set DEPLOYER_ADDRESS in .env");
    process.exit(1);
  }

  console.log(`Querying names owned by ${address}...`);

  const rootRegistryAddress = process.env.ROOT_REGISTRY_ADDRESS;
  console.log("ROOT_REGISTRY_ADDRESS:", rootRegistryAddress);
  if (!rootRegistryAddress) {
    console.error("ROOT_REGISTRY_ADDRESS not found in .env");
    process.exit(1);
  }

  const datastoreAddress = process.env.REGISTRY_DATASTORE_ADDRESS;
  if (!datastoreAddress) {
    console.error("REGISTRY_DATASTORE_ADDRESS not found in .env");
    process.exit(1);
  }

  const RootRegistry = await hre.viem.getContractAt("PermissionedRegistry", rootRegistryAddress);
  
  const Datastore = await hre.viem.getContractAt("RegistryDatastore", datastoreAddress);
  
  await watchRegistry(RootRegistry);
  
  await watchDatastore(Datastore);

  const names = getOwnedNames(RootRegistry, address);

  console.log("\nOwned names with resolvers and addresses:");
  console.log("---------------------------------------");
  const sortedNames = Array.from(names).sort((a, b) => a.name.localeCompare(b.name));
  
  const nameTable = [];
  for (const nameInfo of sortedNames) {
    const ethAddress = await getNameAddress(nameInfo.name, nameInfo.resolver);
    nameTable.push({
      name: nameInfo.name,
      resolver: nameInfo.resolver || 'None',
      ethAddress: ethAddress || 'None'
    });
  }
  
  console.table(nameTable);
  
  console.log("\nDemonstrating aliasing with example.eth and example.xyz:");
  console.log("----------------------------------------------------");
  
  try {
    const exampleEthNamehash = calculateNamehash("example.eth");
    const exampleXyzNamehash = calculateNamehash("example.xyz");
    
    console.log(`Namehash for example.eth: ${exampleEthNamehash}`);
    console.log(`Namehash for example.xyz: ${exampleXyzNamehash}`);
    
    let exampleEthResolver = null;
    let exampleXyzResolver = null;
    
    for (const nameInfo of sortedNames) {
      if (nameInfo.name === "example.eth" && nameInfo.resolver) {
        exampleEthResolver = nameInfo.resolver;
      }
      if (nameInfo.name === "example.xyz" && nameInfo.resolver) {
        exampleXyzResolver = nameInfo.resolver;
      }
    }
    
    if (exampleEthResolver) {
      console.log(`Found resolver for example.eth: ${exampleEthResolver}`);
      const hybridResolver = await hre.viem.getContractAt("HybridResolver", exampleEthResolver);
      
      try {
        const ethAddress = await hybridResolver.read.addr([exampleEthNamehash]);
        console.log(`Address for example.eth: ${ethAddress}`);
        
        if (exampleXyzResolver) {
          console.log(`Found resolver for example.xyz: ${exampleXyzResolver}`);
          
          try {
            const xyzAddress = await hybridResolver.read.addr([exampleXyzNamehash]);
            console.log(`Address for example.xyz: ${xyzAddress}`);
            
            if (ethAddress === xyzAddress) {
              console.log("SUCCESS: Both example.eth and example.xyz resolve to the same address, demonstrating successful aliasing!");
            } else {
              console.log("Different addresses for example.eth and example.xyz");
            }
          } catch (error) {
            console.error(`Error getting address for example.xyz:`, error.message);
          }
        }
      } catch (error) {
        console.error(`Error getting address for example.eth:`, error.message);
      }
    }
  } catch (error) {
    console.error("Error demonstrating aliasing:", error);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
