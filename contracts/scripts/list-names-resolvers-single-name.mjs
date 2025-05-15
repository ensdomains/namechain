// SPDX-License-Identifier: MIT
import { ethers } from "hardhat";
import { dnsEncodeName } from "./utils/dns";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Listing names with the account:", deployer.address);

  // Get the root registry
  const rootRegistry = await ethers.getContractAt("PermissionedRegistryV2", process.env.ROOT_REGISTRY_ADDRESS);
  
  // Get the universal resolver
  const universalResolver = await ethers.getContractAt("UniversalResolverV2", process.env.UNIVERSAL_RESOLVER_ADDRESS);
  
  // Function to list names in a registry
  async function listNamesInRegistry(registry, prefix = "") {
    const filter = registry.filters.NameRegistered();
    const events = await registry.queryFilter(filter);
    
    console.log(`\nNames in registry ${await registry.address} (prefix: ${prefix || "root"}):`);
    console.log("-----------------------------------------------------");
    
    for (const event of events) {
      const label = event.args.label;
      const owner = event.args.owner;
      const subregistry = await registry.getSubregistry(label);
      const resolver = await registry.getResolver(label);
      
      const fullName = prefix ? `${label}.${prefix}` : label;
      console.log(`Name: ${fullName}`);
      console.log(`Owner: ${owner}`);
      console.log(`Subregistry: ${subregistry}`);
      console.log(`Resolver: ${resolver}`);
      
      // If resolver exists, get ETH address
      if (resolver !== ethers.constants.AddressZero) {
        try {
          // Try to get the ETH address using SingleNameResolver interface
          const singleNameResolver = await ethers.getContractAt("SingleNameResolver", resolver);
          const ethAddress = await singleNameResolver.addr();
          console.log(`ETH Address: ${ethAddress}`);
          
          // Try to get text records
          try {
            const email = await singleNameResolver.text("email");
            if (email) {
              console.log(`Email: ${email}`);
            }
          } catch (error) {
            console.log(`No email text record found`);
          }
          
          // Try to get content hash
          try {
            const contentHash = await singleNameResolver.contenthash();
            if (contentHash && contentHash !== "0x") {
              console.log(`Content Hash: ${contentHash}`);
            }
          } catch (error) {
            console.log(`No content hash found`);
          }
        } catch (error) {
          console.log(`Error getting resolver data: ${error.message}`);
        }
        
        // Try resolving through UniversalResolver
        try {
          const encodedName = dnsEncodeName(fullName);
          const addrSelector = "0x3b3b57de"; // addr(bytes32)
          const [result, resolverAddr] = await universalResolver.resolve(encodedName, addrSelector);
          console.log(`Resolved via UniversalResolver: ${result}`);
          console.log(`Using resolver: ${resolverAddr}`);
        } catch (error) {
          console.log(`Error resolving via UniversalResolver: ${error.message}`);
        }
      }
      
      console.log("-----------------------------------------------------");
      
      // Recursively list names in subregistry
      if (subregistry !== ethers.constants.AddressZero) {
        const subregistryContract = await ethers.getContractAt("PermissionedRegistryV2", subregistry);
        await listNamesInRegistry(subregistryContract, fullName);
      }
    }
  }
  
  // Start listing from the root registry
  await listNamesInRegistry(rootRegistry);
  
  console.log("\nListing complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
