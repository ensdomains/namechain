import hre from "hardhat";
import { labelhash, encodeFunctionData, zeroAddress, decodeEventLog, namehash, decodeAbiParameters } from "viem";
import { dnsEncodeName } from "../lib/ens-contracts/test/fixtures/dnsEncodeName.js";
import fs from "fs";
const MAX_EXPIRY = (1n << 64n) - 1n;

async function main() {
  console.log("Starting deployment...");
  
  const [deployer] = await hre.viem.getWalletClients();
  console.log("Deploying with account:", deployer.account.address);

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

  // Deploy resolver
  console.log("Deploying OwnedResolver...");
  const ownedResolverImpl = await hre.viem.deployContract("OwnedResolver");
  console.log("OwnedResolver implementation deployed to:", ownedResolverImpl.address);

  console.log("Deploying VerifiableFactory...");
  const verifiableFactory = await hre.viem.deployContract(
    "@ensdomains/verifiable-factory/VerifiableFactory.sol:VerifiableFactory"
  );
  console.log("VerifiableFactory deployed to:", verifiableFactory.address);
  console.log(1);
  // Deploy resolver proxy
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
  console.log(2);
  const publicClient = await hre.viem.getPublicClient();
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  console.log('Transaction receipt:', receipt);
  
  if (!receipt || !receipt.logs) {
    throw new Error('No logs found in transaction receipt');
  }
  
  console.log('Number of logs:', receipt.logs.length);
  const logs = Array.isArray(receipt.logs) ? receipt.logs : Object.values(receipt.logs);
  
  let log
  logs.map(l => {
    console.log('Log entry:', {
      address: l.address,
      data: l.data,
      topics: l.topics
    });
    try {
      // Skip logs that don't match our contract address
      if (l.address.toLowerCase() !== verifiableFactory.address.toLowerCase()) {
        return null;
      }
      
      log = decodeEventLog({
        abi: verifiableFactory.abi,
        data: l.data,
        topics: l.topics,
      });
      console.log('Decoded log:', log);
    } catch (error) {
      console.log('Error decoding log:', error.message);
    }
  })
  // .filter(l => l && l.eventName === 'ProxyDeployed')[0]; // Get first matching log or undefined
  console.log(3, log);
  if (!log) {
    throw new Error('ProxyDeployed event not found in transaction logs');
  }

  console.log(4);
  const ownedResolver = await hre.viem.getContractAt("OwnedResolver", log.args.proxyAddress);
  console.log("OwnedResolver proxy deployed to:", ownedResolver.address);

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
  console.log(5);
  // Register subnames under example.eth using its subregistry
  const subnames = ["foo.example.eth", "bar.example.eth", "sub.example.eth"];
  const exampleSubregistry = await hre.viem.getContractAt(
    "PermissionedRegistry",
    await ethRegistry.read.getSubregistry(["example"])
  );
  console.log(6);
  for (const subname of subnames) {
    console.log(`Registering ${subname}...`);
    const label = subname.split(".")[0];  // Get the first part before any dots
    await exampleSubregistry.write.register([
      label,
      deployer.account.address,
      zeroAddress, // No further subregistry
      ownedResolver.address,
      (1n << 256n) - 1n, // ROLES.ALL
      MAX_EXPIRY,
    ]);

    // Set ETH address record in resolver
    console.log(`Setting address record for ${subname}...`);
    await ownedResolver.write.setAddr([
      namehash(subname),
      deployer.account.address
    ]);
    const result = await ownedResolver.read.addr([
      namehash(subname)
    ]);
    console.log(result);
  }

  console.log("\nDeployment Summary:");
  console.log("-------------------");
  console.log("RegistryDatastore:", datastore.address);
  console.log("RootRegistry:", rootRegistry.address);
  console.log("ETHRegistry:", ethRegistry.address);
  console.log("OwnedResolver Implementation:", ownedResolverImpl.address);
  console.log("OwnedResolver Proxy:", ownedResolver.address);
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
OWNED_RESOLVER_PROXY_ADDRESS=${ownedResolver.address}
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
      // Encode name using dnsEncodeName
      const encodedName = dnsEncodeName(name)
      
      // Create calldata for addr(bytes32) - function selector is 0x3b3b57de
      // Append the namehash of the name to the selector
      const node = namehash(name);
      const callData = "0x3b3b57de" + node.slice(2); // remove 0x from node
      
      // Resolve the name using UniversalResolver
      const result = await universalResolver.read.resolve([
        encodedName,
        callData
      ]);
      console.log("✓ Successfully resolved");
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