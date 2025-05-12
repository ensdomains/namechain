import hre from "hardhat";
import { labelhash, encodeFunctionData, zeroAddress, decodeEventLog, namehash, decodeAbiParameters } from "viem";
import { packetToBytes } from 'viem/ens'
import { toHex } from 'viem/utils'
import fs from "fs";
const MAX_EXPIRY = (1n << 64n) - 1n;

function dnsEncodeName(name) {
  const bytes = packetToBytes(name)
  return toHex(bytes)
}

async function deployResolver(deployer, verifiableFactory, ownedResolverImpl) {
  const salt = BigInt(labelhash(new Date().toISOString()));
  const hash = await verifiableFactory.write.deployProxy([
    ownedResolverImpl.address,
    salt,
    encodeFunctionData({
      abi: ownedResolverImpl.abi,
      functionName: "initialize",
      args: [deployer.account.address],
    }),
  ]);
  
  const publicClient = await hre.viem.getPublicClient();
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  
  if (!receipt || !receipt.logs) {
    throw new Error('No logs found in transaction receipt');
  }
  
  const logs = Array.isArray(receipt.logs) ? receipt.logs : Object.values(receipt.logs);
  
  let log;
  for (const l of logs) {
    if (l.address.toLowerCase() !== verifiableFactory.address.toLowerCase()) {
      continue;
    }
    
    try {
      log = decodeEventLog({
        abi: verifiableFactory.abi,
        data: l.data,
        topics: l.topics,
      });
      break;
    } catch (error) {
      console.log('Error decoding log:', error.message);
    }
  }
  
  if (!log) {
    throw new Error('ProxyDeployed event not found in transaction logs');
  }

  const ownedResolver = await hre.viem.getContractAt("OwnedResolver", log.args.proxyAddress);
  return ownedResolver;
}

async function main() {
  console.log("Starting deployment...");
  
  const [deployer, newOwner] = await hre.viem.getWalletClients();
  console.log("Deploying with account:", deployer.account.address);
  console.log("New owner address:", newOwner.account.address);

  // Deploy core contracts
  console.log("Deploying RegistryDatastore...");
  const datastore = await hre.viem.deployContract("RegistryDatastore");
  console.log("RegistryDatastore deployed to:", datastore.address);

  console.log("Deploying RootRegistry...");
  const rootRegistry = await hre.viem.deployContract("PermissionedRegistry", [
    datastore.address,
    zeroAddress,
    (1n << 256n) - 1n, // ROLES.ALL
  ]);
  console.log("RootRegistry deployed to:", rootRegistry.address);

  console.log("Deploying ETHRegistry...");
  const ethRegistry = await hre.viem.deployContract("PermissionedRegistry", [
    datastore.address,
    zeroAddress,
    (1n << 256n) - 1n, // ROLES.ALL
  ]);
  console.log("ETHRegistry deployed to:", ethRegistry.address);

  // Deploy resolver implementation
  console.log("Deploying OwnedResolver implementation...");
  const ownedResolverImpl = await hre.viem.deployContract("OwnedResolver");
  console.log("OwnedResolver implementation deployed to:", ownedResolverImpl.address);

  console.log("Deploying VerifiableFactory...");
  const verifiableFactory = await hre.viem.deployContract(
    "@ensdomains/verifiable-factory/VerifiableFactory.sol:VerifiableFactory"
  );
  console.log("VerifiableFactory deployed to:", verifiableFactory.address);

  // Deploy UniversalResolver
  console.log("Deploying UniversalResolver...");
  const universalResolver = await hre.viem.deployContract(
    "UniversalResolver",
    [rootRegistry.address, ["x-batch-gateway:true"]]
  );
  console.log("UniversalResolver deployed to:", universalResolver.address);

  // Register .eth TLD
  console.log("Registering .eth TLD...");
  await rootRegistry.write.register([
    "eth",
    deployer.account.address,
    ethRegistry.address,
    zeroAddress,
    (1n << 256n) - 1n, // ROLES.ALL
    MAX_EXPIRY,
  ]);

  // Register some example domains
  const domains = ["example.eth", "test.eth", "demo.eth"];
  
  for (const domain of domains) {
    console.log(`Registering ${domain}...`);
    const name = domain.replace(".eth", "");
    
    // For example.eth, we'll create a subregistry to handle its subnames
    const needsSubregistry = domain === "example.eth";
    
    // Deploy a new registry for example.eth subnames
    let subregistry = zeroAddress;
    if (needsSubregistry) {
      console.log(`Deploying subregistry for ${domain}...`);
      subregistry = (await hre.viem.deployContract("PermissionedRegistry", [
        datastore.address,
        zeroAddress,
        (1n << 256n) - 1n, // ROLES.ALL
      ])).address;
      console.log(`Subregistry for ${domain} deployed to:`, subregistry);
    }
    
    // Deploy a new resolver for this domain
    console.log(`Deploying resolver for ${domain}...`);
    const ownedResolver = await deployResolver(deployer, verifiableFactory, ownedResolverImpl);
    console.log(`Resolver for ${domain} deployed to:`, ownedResolver.address);
    
    await ethRegistry.write.register([
      name,
      deployer.account.address,
      subregistry, // Use subregistry for example.eth, zeroAddress for others
      ownedResolver.address,
      (1n << 256n) - 1n, // ROLES.ALL
      MAX_EXPIRY,
    ]);

    // Set ETH address record in resolver
    console.log(`Setting address record for ${domain}...`);
    await ownedResolver.write.setAddr([
      namehash(domain),
      deployer.account.address
    ]);
    const result = await ownedResolver.read.addr([
      namehash(domain)
    ]);
    console.log(result);
  }

  // Register subnames under example.eth using its subregistry
  const subnames = ["foo.example.eth", "bar.example.eth", "sub.example.eth"];
  const exampleSubregistry = await hre.viem.getContractAt(
    "PermissionedRegistry",
    await ethRegistry.read.getSubregistry(["example"])
  );

  for (const subname of subnames) {
    console.log(`Registering ${subname}...`);
    const label = subname.split(".")[0];  // Get the first part before any dots
    
    // Deploy a new resolver for this subname
    console.log(`Deploying resolver for ${subname}...`);
    const ownedResolver = await deployResolver(deployer, verifiableFactory, ownedResolverImpl);
    console.log(`Resolver for ${subname} deployed to:`, ownedResolver.address);
    
    // For bar.example.eth, register it to the new owner
    const owner = subname === "bar.example.eth" ? newOwner.account.address : deployer.account.address;
    
    await exampleSubregistry.write.register([
      label,
      owner,
      zeroAddress, // No further subregistry
      ownedResolver.address,
      (1n << 256n) - 1n, // ROLES.ALL
      MAX_EXPIRY,
    ]);

    // Set ETH address record in resolver
    console.log(`Setting address record for ${subname}...`);
    await ownedResolver.write.setAddr([
      namehash(subname),
      owner
    ]);
    const result = await ownedResolver.read.addr([
      namehash(subname)
    ]);
    console.log(result);
  }

  // Transfer ownership of bar.example.eth's resolver to the new owner
  console.log("\nTransferring resolver ownership for bar.example.eth...");
  const barResolver = await hre.viem.getContractAt(
    "OwnedResolver",
    await exampleSubregistry.read.getResolver(["bar"])
  );
  const transferTx = await barResolver.write.transferOwnership([newOwner.account.address]);
  console.log("Waiting for ownership transfer transaction to be mined...");
  const publicClient = await hre.viem.getPublicClient();
  await publicClient.waitForTransactionReceipt({ hash: transferTx });
  console.log("Resolver ownership transferred to:", newOwner.account.address);

  // New owner updates the address record
  console.log("\nNew owner updating address record for bar.example.eth...");
  console.log(newOwner);
  
  // Create a new contract instance with the new owner's wallet client
  const barResolverWithNewOwner = await hre.viem.getContractAt(
    "OwnedResolver",
    barResolver.address,
    { walletClient: newOwner }
  );

  // Verify the new owner is actually the owner
  const currentOwner = await barResolverWithNewOwner.read.owner();
  console.log("Current resolver owner:", currentOwner);
  console.log("New owner address:", newOwner.account.address);
  if (currentOwner.toLowerCase() !== newOwner.account.address.toLowerCase()) {
    throw new Error("Ownership transfer failed - new owner is not the current owner");
  }

  // Use the new owner's contract instance to set the address
  const setAddrTx = await barResolverWithNewOwner.write.setAddr(
    [namehash("bar.example.eth"), newOwner.account.address],
    { account: newOwner.account }
  );
  console.log("Waiting for setAddr transaction to be mined...");
  await publicClient.waitForTransactionReceipt({ hash: setAddrTx });
  
  const newResult = await barResolverWithNewOwner.read.addr([
    namehash("bar.example.eth")
  ]);
  console.log("New address record set to:", newResult);

  console.log("\nDeployment Summary:");
  console.log("-------------------");
  console.log("RegistryDatastore:", datastore.address);
  console.log("RootRegistry:", rootRegistry.address);
  console.log("ETHRegistry:", ethRegistry.address);
  console.log("OwnedResolver Implementation:", ownedResolverImpl.address);
  console.log("VerifiableFactory:", verifiableFactory.address);
  console.log("UniversalResolver:", universalResolver.address);

  // Save addresses to .env file
  let existingEnv = '';
  try {
    existingEnv = fs.readFileSync('.env', 'utf8');
  } catch (error) {
    // File doesn't exist yet, that's fine
  }

  const envContent = `
# Contract Addresses
REGISTRY_DATASTORE_ADDRESS=${datastore.address}
ROOT_REGISTRY_ADDRESS=${rootRegistry.address}
ETH_REGISTRY_ADDRESS=${ethRegistry.address}
OWNED_RESOLVER_IMPL_ADDRESS=${ownedResolverImpl.address}
VERIFIABLE_FACTORY_ADDRESS=${verifiableFactory.address}
UNIVERSAL_RESOLVER_ADDRESS=${universalResolver.address}
`;

  // Only append if addresses aren't already in the file
  if (!existingEnv.includes('REGISTRY_DATASTORE_ADDRESS=')) {
    fs.writeFileSync('.env', envContent.trim() + '\n', { flag: 'a' });
    console.log("\nContract addresses have been saved to .env file");
  } else {
    console.log("\nContract addresses already exist in .env file");
  }

  console.log("\nRegistered Domains:");
  console.log("------------------");
  domains.forEach(domain => console.log(domain));
  console.log("\nRegistered Subnames:");
  console.log("-------------------");
  subnames.forEach(subname => console.log(subname));

  // Verify all names are properly set using UniversalResolver
  console.log("\nVerifying name resolutions:");
  console.log("-------------------------");
  
  // Check all names (both domains and subnames)
  const allNames = [...domains, ...subnames];
  for (const name of allNames) {
    console.log(`\n${name}:`);
    try {
      const encodedName = dnsEncodeName(name);
      
      // Get the resolver address first
      let resolverAddress;
      if (name.endsWith('.eth')) {
        const label = name.split('.')[0];
        if (name === 'example.eth') {
          // For example.eth, get resolver from ETH registry
          resolverAddress = await ethRegistry.read.getResolver([label]);
        } else if (name.includes('example.eth')) {
          // For subnames of example.eth, get resolver from example subregistry
          const subLabel = name.split('.')[0];
          resolverAddress = await exampleSubregistry.read.getResolver([subLabel]);
        } else {
          // For other .eth names, get resolver from ETH registry
          resolverAddress = await ethRegistry.read.getResolver([label]);
        }
      }
      
      // Create calldata for addr(bytes32) - function selector is 0x3b3b57de
      // Append the namehash of the name to the selector
      const node = namehash(name);
      const callData = "0x3b3b57de" + node.slice(2); // remove 0x from node
      // Resolve the name using UniversalResolver
      const result = await universalResolver.read.resolve([
        encodedName,
        callData
      ]);
      console.log(`✓ Successfully resolved (Resolver: ${resolverAddress})`);
      if (result.data !== "0x") {
        // Decode the address using ABI parameters
        const [addr] = decodeAbiParameters(
          [{ type: 'address' }],
          result[0]
        );
        console.log("- Address:", addr);
      }
    } catch (error) {
      console.log("✗ Failed to resolve:", error.message);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 