const hre = require("hardhat");
const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");
require("dotenv").config({ path: path.join(__dirname, "..", ".env") });

const nameState = {
  registries: {},
  relinquished: {},
  resolvers: {},
  owners: {}
};

function handleNewSubname(registry, labelHash, label) {
  if (!nameState.registries[registry]) {
    nameState.registries[registry] = {};
  }
  
  nameState.registries[registry][labelHash] = {
    label,
    subregistry: null
  };
}

function handleSubregistryUpdate(registry, labelHash, subregistry) {
  if (!nameState.registries[registry]) {
    nameState.registries[registry] = {};
  }
  
  if (!nameState.registries[registry][labelHash]) {
    nameState.registries[registry][labelHash] = {
      label: `unknown-${labelHash}`,
      subregistry: null
    };
  }
  
  nameState.registries[registry][labelHash].subregistry = subregistry;
}

function handleResolverUpdate(registry, labelHash, resolver) {
  if (!nameState.resolvers[registry]) {
    nameState.resolvers[registry] = {};
  }
  
  nameState.resolvers[registry][labelHash] = resolver;
}

function handleOwnershipUpdate(registry, labelHash, owner) {
  if (!nameState.owners[registry]) {
    nameState.owners[registry] = {};
  }
  
  nameState.owners[registry][labelHash] = owner;
}

function getFullName(registry, labelHash, parentName = "") {
  const registryData = nameState.registries[registry];
  if (!registryData || !registryData[labelHash]) {
    return parentName ? `unknown-${labelHash}.${parentName}` : `unknown-${labelHash}`;
  }
  
  const { label } = registryData[labelHash];
  return parentName ? `${label}.${parentName}` : label;
}

async function getOwnedNames(address) {
  const ownedNames = [];
  const rootRegistryAddress = process.env.ROOT_REGISTRY_ADDRESS;
  
  if (!rootRegistryAddress) {
    console.error("ROOT_REGISTRY_ADDRESS not found in .env file");
    return ownedNames;
  }
  
  console.log(`ROOT_REGISTRY_ADDRESS: ${rootRegistryAddress}`);
  
  for (const registry in nameState.registries) {
    const registryData = nameState.registries[registry];
    
    for (const labelHash in registryData) {
      const { label, subregistry } = registryData[labelHash];
      
      if (nameState.owners[registry] && 
          nameState.owners[registry][labelHash] === address &&
          !nameState.relinquished[registry]?.[labelHash]) {
        
        let parentRegistry = null;
        let parentLabelHash = null;
        let parentName = "";
        
        for (const potentialParent in nameState.registries) {
          const potentialParentData = nameState.registries[potentialParent];
          
          for (const potentialParentLabelHash in potentialParentData) {
            if (potentialParentData[potentialParentLabelHash].subregistry === registry) {
              parentRegistry = potentialParent;
              parentLabelHash = potentialParentLabelHash;
              break;
            }
          }
          
          if (parentRegistry) break;
        }
        
        if (parentRegistry) {
          parentName = getFullName(parentRegistry, parentLabelHash);
        }
        
        const fullName = getFullName(registry, labelHash, parentName);
        
        let resolver = null;
        if (nameState.resolvers[registry] && nameState.resolvers[registry][labelHash]) {
          resolver = nameState.resolvers[registry][labelHash];
        }
        
        ownedNames.push({
          name: fullName,
          registry,
          labelHash,
          resolver,
          subregistry
        });
        
        if (subregistry) {
        }
      }
    }
  }
  
  return ownedNames;
}

async function main() {
  const [deployer] = await ethers.getSigners();
  const address = deployer.address;
  
  console.log(`Querying names owned by ${address}...`);
  
  const RootRegistry = await ethers.getContractFactory("RootRegistry");
  const ETHRegistry = await ethers.getContractFactory("ETHRegistry");
  const RegistryDatastore = await ethers.getContractFactory("RegistryDatastore");
  const SimplifiedHybridResolver = await ethers.getContractFactory("SimplifiedHybridResolver");
  
  const rootRegistryAddress = process.env.ROOT_REGISTRY_ADDRESS;
  const ethRegistryAddress = process.env.ETH_REGISTRY_ADDRESS;
  const xyzRegistryAddress = process.env.XYZ_REGISTRY_ADDRESS;
  const exampleRegistryAddress = process.env.EXAMPLE_REGISTRY_ADDRESS;
  
  if (!rootRegistryAddress) {
    console.error("ROOT_REGISTRY_ADDRESS not found in .env file");
    return;
  }
  
  const rootRegistry = RootRegistry.attach(rootRegistryAddress);
  const ethRegistry = ETHRegistry.attach(ethRegistryAddress);
  const xyzRegistry = ETHRegistry.attach(xyzRegistryAddress);
  const exampleRegistry = ETHRegistry.attach(exampleRegistryAddress);
  const registryDatastore = RegistryDatastore.attach(await rootRegistry.datastore());
  
  const rootRegistryFilter = rootRegistry.filters.NewSubname();
  const rootRegistryEvents = await rootRegistry.queryFilter(rootRegistryFilter);
  
  for (const event of rootRegistryEvents) {
    handleNewSubname(rootRegistryAddress, event.args.labelHash, event.args.label);
    handleOwnershipUpdate(rootRegistryAddress, event.args.labelHash, address);
    console.log(`Updated owner for ${event.args.label} to ${address}`);
  }
  
  const ethRegistryFilter = ethRegistry.filters.NewSubname();
  const ethRegistryEvents = await ethRegistry.queryFilter(ethRegistryFilter);
  
  for (const event of ethRegistryEvents) {
    handleNewSubname(ethRegistryAddress, event.args.labelHash, event.args.label);
    handleOwnershipUpdate(ethRegistryAddress, event.args.labelHash, address);
    console.log(`Updated owner for ${event.args.label} to ${address}`);
  }
  
  const xyzRegistryFilter = xyzRegistry.filters.NewSubname();
  const xyzRegistryEvents = await xyzRegistry.queryFilter(xyzRegistryFilter);
  
  for (const event of xyzRegistryEvents) {
    handleNewSubname(xyzRegistryAddress, event.args.labelHash, event.args.label);
    handleOwnershipUpdate(xyzRegistryAddress, event.args.labelHash, address);
    console.log(`Updated owner for ${event.args.label} to ${address}`);
  }
  
  const exampleRegistryFilter = exampleRegistry.filters.NewSubname();
  const exampleRegistryEvents = await exampleRegistry.queryFilter(exampleRegistryFilter);
  
  for (const event of exampleRegistryEvents) {
    handleNewSubname(exampleRegistryAddress, event.args.labelHash, event.args.label);
    handleOwnershipUpdate(exampleRegistryAddress, event.args.labelHash, address);
    console.log(`Updated owner for ${event.args.label} to ${address}`);
  }
  
  const subregistryFilter = registryDatastore.filters.SubregistryUpdate();
  const subregistryEvents = await registryDatastore.queryFilter(subregistryFilter);
  
  for (const event of subregistryEvents) {
    const registry = event.args.registry;
    const labelHash = event.args.labelHash;
    const subregistry = event.args.subregistry;
    
    handleSubregistryUpdate(registry, labelHash, subregistry);
    console.log(`Updated subregistry for ${nameState.registries[registry]?.[labelHash]?.label || labelHash} to ${subregistry}`);
  }
  
  const resolverFilter = registryDatastore.filters.ResolverUpdate();
  const resolverEvents = await registryDatastore.queryFilter(resolverFilter);
  
  for (const event of resolverEvents) {
    const registry = event.args.registry;
    const labelHash = event.args.labelHash;
    const resolver = event.args.resolver;
    
    handleResolverUpdate(registry, labelHash, resolver);
    console.log(`Updated resolver for ${nameState.registries[registry]?.[labelHash]?.label || labelHash} to ${resolver}`);
  }
  
  const ownedNames = await getOwnedNames(address);
  
  const nameTable = [];
  
  for (const ownedName of ownedNames) {
    let ethAddress = null;
    
    if (ownedName.resolver && ownedName.resolver !== ethers.constants.AddressZero) {
      try {
        const resolver = SimplifiedHybridResolver.attach(ownedName.resolver);
        const namehash = ethers.utils.namehash(ownedName.name);
        ethAddress = await resolver.addr(namehash);
      } catch (error) {
        console.error(`Error getting ETH address for ${ownedName.name}: ${error.message}`);
      }
    }
    
    nameTable.push({
      name: ownedName.name,
      resolver: ownedName.resolver,
      ethAddress: ethAddress,
      owner: address
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
  
  const exampleEthResolver = nameTable.find(entry => entry.name === "example.eth")?.resolver;
  console.log(`Found resolver for example.eth: ${exampleEthResolver}`);
  
  let exampleEthAddress = null;
  if (exampleEthResolver) {
    try {
      const resolver = SimplifiedHybridResolver.attach(exampleEthResolver);
      exampleEthAddress = await resolver.addr(namehashExampleEth);
      console.log(`Address for example.eth: ${exampleEthAddress}`);
    } catch (error) {
      console.error(`Error getting address for example.eth: ${error.message}`);
    }
  }
  
  const exampleXyzResolver = nameTable.find(entry => entry.name === "example.xyz")?.resolver;
  console.log(`Found resolver for example.xyz: ${exampleXyzResolver}`);
  
  let exampleXyzAddress = null;
  if (exampleXyzResolver) {
    try {
      const resolver = SimplifiedHybridResolver.attach(exampleXyzResolver);
      exampleXyzAddress = await resolver.addr(namehashExampleXyz);
      console.log(`Address for example.xyz: ${exampleXyzAddress}`);
    } catch (error) {
      console.error(`Error getting address for example.xyz: ${error.message}`);
    }
  }
  
  if (exampleEthAddress && exampleXyzAddress && exampleEthAddress === exampleXyzAddress) {
    console.log("SUCCESS: Both example.eth and example.xyz resolve to the same address, demonstrating successful aliasing!");
  } else {
    console.log("FAILURE: Aliasing not working correctly. The addresses are different or could not be resolved.");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
