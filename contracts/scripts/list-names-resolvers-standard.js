import hre from "hardhat";
import fs from "fs";
import path from "path";
import hardhat from "hardhat";
const { ethers } = hardhat;
import dotenv from "dotenv";

dotenv.config({ path: path.join(__dirname, "..", ".env") });

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log(`Querying names owned by ${deployer.address}...`);
  
  const ROOT_REGISTRY_ADDRESS = process.env.ROOT_REGISTRY_ADDRESS;
  console.log(`ROOT_REGISTRY_ADDRESS: ${ROOT_REGISTRY_ADDRESS}`);
  
  const RootRegistry = await ethers.getContractFactory("RootRegistry");
  const rootRegistry = RootRegistry.attach(ROOT_REGISTRY_ADDRESS);
  
  const registryDatastoreAddress = await rootRegistry.datastore();
  const RegistryDatastore = await ethers.getContractFactory("RegistryDatastore");
  const registryDatastore = RegistryDatastore.attach(registryDatastoreAddress);
  
  const ENSStandardResolver = await ethers.getContractFactory("ENSStandardResolver");
  
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
  
  const ownedNames = await getOwnedNames(nameState, deployer.address);
  
  const nameTable = [];
  
  for (const name of ownedNames) {
    const namehash = ethers.utils.namehash(name);
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
      
      const resolverAddr = await currentRegistry.getResolver(component);
      
      if (resolverAddr !== ethers.constants.AddressZero) {
        resolverAddress = resolverAddr;
      }
      
      if (i > 0) {
        const subregistryAddr = await currentRegistry.getSubregistry(component);
        
        if (subregistryAddr !== ethers.constants.AddressZero) {
          const Registry = await ethers.getContractFactory("PermissionedRegistry");
          currentRegistry = Registry.attach(subregistryAddr);
        } else {
          break;
        }
      }
    }
    
    if (resolverAddress) {
      const resolver = ENSStandardResolver.attach(resolverAddress);
      
      try {
        ethAddress = await resolver.addr(namehash);
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
            const labelHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(component));
            const balance = await currentRegistry.balanceOf(deployer.address, labelHash);
            
            if (balance.gt(0)) {
              owner = deployer.address;
            }
          }
          
          if (i > 0) {
            const subregistryAddr = await currentRegistry.getSubregistry(component);
            
            if (subregistryAddr !== ethers.constants.AddressZero) {
              const Registry = await ethers.getContractFactory("PermissionedRegistry");
              currentRegistry = Registry.attach(subregistryAddr);
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
  
  const namehashExampleEth = ethers.utils.namehash("example.eth");
  const namehashExampleXyz = ethers.utils.namehash("example.xyz");
  
  console.log(`Namehash for example.eth: ${namehashExampleEth}`);
  console.log(`Namehash for example.xyz: ${namehashExampleXyz}`);
  
  const ethRegistry = await rootRegistry.getSubregistry("eth");
  const PermissionedRegistry = await ethers.getContractFactory("PermissionedRegistry");
  const ethRegistryContract = PermissionedRegistry.attach(ethRegistry);
  const exampleEthResolverAddress = await ethRegistryContract.getResolver("example");
  
  console.log(`Found resolver for example.eth: ${exampleEthResolverAddress}`);
  
  if (exampleEthResolverAddress !== ethers.constants.AddressZero) {
    const exampleEthResolver = ENSStandardResolver.attach(exampleEthResolverAddress);
    const exampleEthAddress = await exampleEthResolver.addr(namehashExampleEth);
    console.log(`Address for example.eth: ${exampleEthAddress}`);
    
    const xyzRegistry = await rootRegistry.getSubregistry("xyz");
    const xyzRegistryContract = PermissionedRegistry.attach(xyzRegistry);
    const exampleXyzResolverAddress = await xyzRegistryContract.getResolver("example");
    
    console.log(`Found resolver for example.xyz: ${exampleXyzResolverAddress}`);
    
    if (exampleXyzResolverAddress !== ethers.constants.AddressZero) {
      const exampleXyzResolver = ENSStandardResolver.attach(exampleXyzResolverAddress);
      const exampleXyzAddress = await exampleXyzResolver.addr(namehashExampleXyz);
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
  const exampleLabelHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(exampleLabel));
  console.log(`Label: "${exampleLabel}"`);
  console.log(`Computed labelhash: ${exampleLabelHash}`);
  
  if (exampleEthResolverAddress !== ethers.constants.AddressZero) {
    const exampleEthResolver = ENSStandardResolver.attach(exampleEthResolverAddress);
    const storedLabelHash = await exampleEthResolver.getLabelHash(namehashExampleEth);
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
  const registryAddress = registry.address;
  
  if (!nameState.registries[registryAddress]) {
    nameState.registries[registryAddress] = {
      type: "Registry",
      names: {}
    };
  }
  
  const newSubnameFilter = registry.filters.NewSubname();
  const newSubnameEvents = await registry.queryFilter(newSubnameFilter);
  
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
  
  const transferSingleFilter = registry.filters.TransferSingle();
  const transferSingleEvents = await registry.queryFilter(transferSingleFilter);
  
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
  
  const nameRelinquishedFilter = registry.filters.NameRelinquished();
  const nameRelinquishedEvents = await registry.queryFilter(nameRelinquishedFilter);
  
  for (const event of nameRelinquishedEvents) {
    const { labelHash } = event.args;
    
    if (!nameState.registries[registryAddress].names[labelHash]) {
      continue;
    }
    
    const name = nameState.registries[registryAddress].names[labelHash];
    
    if (nameState.names[name]) {
      nameState.names[name].owner = ethers.constants.AddressZero;
    }
  }
  
  const subregistryUpdateFilter = registry.filters.SubregistryUpdate();
  const subregistryUpdateEvents = await registry.queryFilter(subregistryUpdateFilter);
  
  for (const event of subregistryUpdateEvents) {
    const { labelHash, subregistry } = event.args;
    
    if (!nameState.registries[registryAddress].names[labelHash]) {
      continue;
    }
    
    const name = nameState.registries[registryAddress].names[labelHash];
    
    if (subregistry === ethers.constants.AddressZero) {
      continue;
    }
    
    const Registry = await ethers.getContractFactory("PermissionedRegistry");
    const subregistryContract = Registry.attach(subregistry);
    await processRegistryEvents(nameState, subregistryContract, name);
  }
}

async function processDatastoreEvents(nameState, datastore) {
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
          const Registry = await ethers.getContractFactory("PermissionedRegistry");
          const registryContract = Registry.attach(registryAddress);
          
          const balance = await registryContract.balanceOf(address, nameData.labelHash);
          
          if (balance.gt(0)) {
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
