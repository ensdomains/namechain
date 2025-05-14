import hre from "hardhat";
import fs from "fs";
import path from "path";
import {
  namehash,
  keccak256,
  stringToBytes,
  zeroAddress,
} from "viem";
import dotenv from "dotenv";

dotenv.config({ path: path.join(__dirname, "..", ".env") });

async function main() {
  const publicClient = await hre.viem.getPublicClient();
  const [walletClient] = await hre.viem.getWalletClients();
  console.log(`Querying names owned by ${walletClient.account.address}...`);
  
  const ROOT_REGISTRY_ADDRESS = process.env.ROOT_REGISTRY_ADDRESS;
  console.log(`ROOT_REGISTRY_ADDRESS: ${ROOT_REGISTRY_ADDRESS}`);
  
  const rootRegistry = await hre.viem.getContractAt("RootRegistry", ROOT_REGISTRY_ADDRESS);
  
  const registryDatastoreAddress = await rootRegistry.read.datastore();
  const registryDatastore = await hre.viem.getContractAt("RegistryDatastore", registryDatastoreAddress);
  
  const nameState = {
    registries: {
      [ROOT_REGISTRY_ADDRESS]: {
        type: "RootRegistry",
        names: {}
      }
    },
    names: {}
  };
  
  await processEvents(nameState, rootRegistry, registryDatastore);
  
  const ownedNames = await getOwnedNames(nameState, walletClient.account.address);
  
  const nameTable = [];
  
  for (const name of ownedNames) {
    const nameHash = namehash(name);
    let resolverAddress = null;
    let ethAddress = null;
    let owner = null;
    
    const nameComponents = name.split('.');
    let currentRegistry = rootRegistry;
    let currentName = '';
    
    for (let i = nameComponents.length - 1; i >= 0; i--) {
      const component = nameComponents[i];
      
      if (currentName === '') {
        currentName = component;
      } else {
        currentName = `${component}.${currentName}`;
      }
      
      const resolverAddr = await currentRegistry.read.getResolver([component]);
      
      if (resolverAddr !== zeroAddress) {
        resolverAddress = resolverAddr;
      }
      
      if (i > 0) {
        const subregistryAddr = await currentRegistry.read.getSubregistry([component]);
        
        if (subregistryAddr !== zeroAddress) {
          currentRegistry = await hre.viem.getContractAt("PermissionedRegistry", subregistryAddr);
        } else {
          break;
        }
      }
    }
    
    if (resolverAddress) {
      const resolver = await hre.viem.getContractAt("ENSStandardResolver", resolverAddress);
      
      try {
        ethAddress = await resolver.read.addr([nameHash]);
      } catch (error) {
        console.error(`Error getting ETH address for ${name}: ${error.message}`);
      }
      
      try {
        const nameComponents = name.split('.');
        let currentRegistry = rootRegistry;
        let currentName = '';
        
        for (let i = nameComponents.length - 1; i >= 0; i--) {
          const component = nameComponents[i];
          
          if (currentName === '') {
            currentName = component;
          } else {
            currentName = `${component}.${currentName}`;
          }
          
          if (i === 0) {
            const labelHash = keccak256(stringToBytes(component));
            const balance = await currentRegistry.read.balanceOf([walletClient.account.address, labelHash]);
            
            if (Number(balance) > 0) {
              owner = walletClient.account.address;
            }
          }
          
          if (i > 0) {
            const subregistryAddr = await currentRegistry.read.getSubregistry([component]);
            
            if (subregistryAddr !== zeroAddress) {
              currentRegistry = await hre.viem.getContractAt("PermissionedRegistry", subregistryAddr);
            } else {
              break;
            }
          }
        }
      } catch (error) {
        console.error(`Error getting owner for ${name}: ${error.message}`);
      }
    }
    
    nameTable.push({
      name,
      resolver: resolverAddress,
      ethAddress,
      owner
    });
  }
  
  console.log("\nOwned names with resolvers and addresses:");
  console.log("---------------------------------------");
  console.table(nameTable);
  
  console.log("\nDemonstrating aliasing with example.eth and example.xyz:");
  console.log("----------------------------------------------------");
  
  const namehashExampleEth = namehash("example.eth");
  const namehashExampleXyz = namehash("example.xyz");
  
  console.log(`Namehash for example.eth: ${namehashExampleEth}`);
  console.log(`Namehash for example.xyz: ${namehashExampleXyz}`);
  
  const ethRegistry = await rootRegistry.read.getSubregistry(["eth"]);
  const ethRegistryContract = await hre.viem.getContractAt("PermissionedRegistry", ethRegistry);
  const exampleEthResolverAddress = await ethRegistryContract.read.getResolver(["example"]);
  
  console.log(`Found resolver for example.eth: ${exampleEthResolverAddress}`);
  
  if (exampleEthResolverAddress !== zeroAddress) {
    const exampleEthResolver = await hre.viem.getContractAt("ENSStandardResolver", exampleEthResolverAddress);
    const exampleEthAddress = await exampleEthResolver.read.addr([namehashExampleEth]);
    console.log(`Address for example.eth: ${exampleEthAddress}`);
    
    const xyzRegistry = await rootRegistry.read.getSubregistry(["xyz"]);
    const xyzRegistryContract = await hre.viem.getContractAt("PermissionedRegistry", xyzRegistry);
    const exampleXyzResolverAddress = await xyzRegistryContract.read.getResolver(["example"]);
    
    console.log(`Found resolver for example.xyz: ${exampleXyzResolverAddress}`);
    
    if (exampleXyzResolverAddress !== zeroAddress) {
      const exampleXyzResolver = await hre.viem.getContractAt("ENSStandardResolver", exampleXyzResolverAddress);
      const exampleXyzAddress = await exampleXyzResolver.read.addr([namehashExampleXyz]);
      console.log(`Address for example.xyz: ${exampleXyzAddress}`);
      
      if (exampleEthAddress === exampleXyzAddress) {
        console.log("SUCCESS: Both example.eth and example.xyz resolve to the same address, demonstrating successful aliasing!");
      } else {
        console.log("FAILURE: example.eth and example.xyz resolve to different addresses.");
      }
    }
  }
  
  console.log("\nLabelhash Computation Example:");
  console.log("----------------------------");
  const exampleLabel = "example";
  const exampleLabelHash = keccak256(stringToBytes(exampleLabel));
  console.log(`Label: "${exampleLabel}"`);
  console.log(`Computed labelhash: ${exampleLabelHash}`);
  
  if (exampleEthResolverAddress !== zeroAddress) {
    const exampleEthResolver = await hre.viem.getContractAt("ENSStandardResolver", exampleEthResolverAddress);
    const storedLabelHash = await exampleEthResolver.read.getLabelHash([namehashExampleEth]);
    console.log(`Stored labelhash for example.eth: ${storedLabelHash}`);
    
    if (storedLabelHash.toString() === exampleLabelHash.toString().replace("0x", "")) {
      console.log("SUCCESS: The stored labelhash matches the computed labelhash!");
    } else {
      console.log("FAILURE: The stored labelhash does not match the computed labelhash.");
    }
  }
}

async function processEvents(nameState, rootRegistry, registryDatastore) {
  await processRegistryEvents(nameState, rootRegistry, "");
  
  await processDatastoreEvents(nameState, registryDatastore);
}

async function processRegistryEvents(nameState, registry, prefix) {
  const registryAddress = await registry.getAddress();
  
  if (!nameState.registries[registryAddress]) {
    nameState.registries[registryAddress] = {
      type: "Registry",
      names: {}
    };
  }
  
  const publicClient = await hre.viem.getPublicClient();
  
  // Get NewSubname events
  const newSubnameFilter = await registry.createEventFilter.NewSubname();
  const newSubnameEvents = await publicClient.getFilterLogs({ filter: newSubnameFilter });
  
  for (const event of newSubnameEvents) {
    const { labelHash, label } = event.args;
    const name = prefix ? `${label}.${prefix}` : label;
    
    nameState.registries[registryAddress].names[labelHash] = name;
    
    if (!nameState.names[name]) {
      nameState.names[name] = {
        registries: [registryAddress],
        labelHash
      };
    } else {
      if (!nameState.names[name].registries.includes(registryAddress)) {
        nameState.names[name].registries.push(registryAddress);
      }
    }
  }
  
  // Get TransferSingle events
  const transferSingleFilter = await registry.createEventFilter.TransferSingle();
  const transferSingleEvents = await publicClient.getFilterLogs({ filter: transferSingleFilter });
  
  for (const event of transferSingleEvents) {
    const { from, to, id } = event.args;
    
    if (!nameState.registries[registryAddress].names[id]) {
      continue;
    }
    
    const name = nameState.registries[registryAddress].names[id];
    
    if (!nameState.names[name]) {
      nameState.names[name] = {
        registries: [registryAddress],
        labelHash: id,
        owner: to
      };
    } else {
      nameState.names[name].owner = to;
    }
  }
  
  // Get NameRelinquished events
  const nameRelinquishedFilter = await registry.createEventFilter.NameRelinquished();
  const nameRelinquishedEvents = await publicClient.getFilterLogs({ filter: nameRelinquishedFilter });
  
  for (const event of nameRelinquishedEvents) {
    const { labelHash } = event.args;
    
    if (!nameState.registries[registryAddress].names[labelHash]) {
      continue;
    }
    
    const name = nameState.registries[registryAddress].names[labelHash];
    
    if (nameState.names[name]) {
      nameState.names[name].owner = zeroAddress;
    }
  }
  
  // Get SubregistryUpdate events
  const subregistryUpdateFilter = await registry.createEventFilter.SubregistryUpdate();
  const subregistryUpdateEvents = await publicClient.getFilterLogs({ filter: subregistryUpdateFilter });
  
  for (const event of subregistryUpdateEvents) {
    const { labelHash, subregistry } = event.args;
    
    if (!nameState.registries[registryAddress].names[labelHash]) {
      continue;
    }
    
    const name = nameState.registries[registryAddress].names[labelHash];
    
    if (subregistry === zeroAddress) {
      continue;
    }
    
    const subregistryContract = await hre.viem.getContractAt("PermissionedRegistry", subregistry);
    await processRegistryEvents(nameState, subregistryContract, name);
  }
}

async function processDatastoreEvents(nameState, datastore) {
  const publicClient = await hre.viem.getPublicClient();
  
  // Get ResolverUpdate events
  const resolverUpdateFilter = await datastore.createEventFilter.ResolverUpdate();
  const resolverUpdateEvents = await publicClient.getFilterLogs({ filter: resolverUpdateFilter });
  
  for (const event of resolverUpdateEvents) {
    const { node, resolver } = event.args;
    
    for (const name in nameState.names) {
      const nameHash = namehash(name);
      
      if (nameHash === node) {
        nameState.names[name].resolver = resolver;
      }
    }
  }
}

async function getOwnedNames(nameState, address) {
  const ownedNames = [];
  
  for (const name in nameState.names) {
    const nameData = nameState.names[name];
    
    if (nameData.owner === address) {
      ownedNames.push(name);
    } else {
      for (const registryAddress of nameData.registries) {
        const registry = nameState.registries[registryAddress];
        
        if (registry.type === "Registry") {
          const registryContract = await hre.viem.getContractAt("PermissionedRegistry", registryAddress);
          
          const balance = await registryContract.read.balanceOf([address, nameData.labelHash]);
          
          if (Number(balance) > 0) {
            ownedNames.push(name);
            break;
          }
        }
      }
    }
  }
  
  return ownedNames;
}

try {
  await main();
  process.exit(0);
} catch (error) {
  console.error(error);
  process.exit(1);
}
