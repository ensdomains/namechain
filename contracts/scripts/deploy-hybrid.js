import hre from "hardhat";
import { labelhash, encodeFunctionData, zeroAddress, decodeEventLog, namehash, decodeAbiParameters } from "viem";
import { packetToBytes } from 'viem/ens';
import { toHex } from 'viem/utils';
import fs from "fs";

const MAX_EXPIRY = (1n << 64n) - 1n;

function dnsEncodeName(name) {
  const bytes = packetToBytes(name);
  return toHex(bytes);
}

async function deployHybridResolver(deployer, verifiableFactory, hybridResolverImpl, registryAddress) {
  const salt = BigInt(labelhash(new Date().toISOString()));
  const hash = await verifiableFactory.write.deployProxy([
    hybridResolverImpl.address,
    salt,
    encodeFunctionData({
      abi: hybridResolverImpl.abi,
      functionName: "initialize",
      args: [deployer.account.address, registryAddress],
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

  const hybridResolver = await hre.viem.getContractAt("HybridResolver", log.args.proxyAddress);
  return hybridResolver;
}

async function deployOwnedResolver(deployer, verifiableFactory, ownedResolverImpl) {
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

async function measureGas(contract, functionName, args) {
  try {
    const gasEstimate = await contract.estimateGas[functionName](args);
    return Number(gasEstimate);
  } catch (error) {
    console.error(`Error estimating gas for ${functionName}:`, error.message);
    return 0;
  }
}

async function estimateReadGas(contract, functionName, args) {
  try {
    const publicClient = await hre.viem.getPublicClient();
    const gasEstimate = await publicClient.estimateGas({
      to: contract.address,
      data: encodeFunctionData({
        abi: contract.abi,
        functionName,
        args,
      }),
    });
    return Number(gasEstimate);
  } catch (error) {
    console.error(`Error estimating gas for ${functionName}:`, error.message);
    return 0;
  }
}

async function main() {
  console.log("Deploying contracts to hardhat node...");
  
  const [deployer] = await hre.viem.getWalletClients();
  console.log("Deploying with account:", deployer.account.address);
  
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
  
  console.log("Deploying HybridResolver implementation...");
  const hybridResolverImpl = await hre.viem.deployContract("HybridResolver");
  console.log("HybridResolver implementation deployed to:", hybridResolverImpl.address);
  
  console.log("Deploying OwnedResolver implementation for gas comparison...");
  const ownedResolverImpl = await hre.viem.deployContract("OwnedResolver");
  console.log("OwnedResolver implementation deployed to:", ownedResolverImpl.address);
  
  console.log("Deploying VerifiableFactory...");
  const verifiableFactory = await hre.viem.deployContract(
    "@ensdomains/verifiable-factory/VerifiableFactory.sol:VerifiableFactory"
  );
  console.log("VerifiableFactory deployed to:", verifiableFactory.address);
  
  console.log("Deploying UniversalResolver...");
  const universalResolver = await hre.viem.deployContract(
    "UniversalResolver",
    [rootRegistry.address, ["x-batch-gateway:true"]]
  );
  console.log("UniversalResolver deployed to:", universalResolver.address);
  
  console.log("Registering .eth TLD...");
  await rootRegistry.write.register([
    "eth",
    deployer.account.address,
    ethRegistry.address,
    zeroAddress,
    (1n << 256n) - 1n, // ROLES.ALL
    MAX_EXPIRY,
  ]);
  console.log("Registered .eth TLD");
  
  console.log("Deploying HybridResolver for .eth...");
  const ethResolver = await deployHybridResolver(deployer, verifiableFactory, hybridResolverImpl, rootRegistry.address);
  console.log("HybridResolver for .eth deployed to:", ethResolver.address);
  
  await rootRegistry.write.setResolver([
    BigInt(labelhash("eth")),
    ethResolver.address,
    MAX_EXPIRY,
    0
  ]);
  console.log("Set resolver for .eth in registry");
  
  const ethNamehash = namehash("eth");
  const ethLabelHash = labelhash("eth");
  console.log("Namehash for .eth:", ethNamehash);
  
  console.log("Mapping namehash to labelHash in resolver...");
  await ethResolver.write.mapNamehash([ethNamehash, BigInt(ethLabelHash), true]);
  console.log("Mapped namehash to labelHash");
  
  console.log("Setting address for .eth...");
  await ethResolver.write.setAddr([ethNamehash, "0x5555555555555555555555555555555555555555"]);
  console.log("Set address for .eth");
  
  console.log("Registering example.eth...");
  
  console.log("Deploying HybridResolver for example.eth...");
  const exampleResolver = await deployHybridResolver(deployer, verifiableFactory, hybridResolverImpl, ethRegistry.address);
  console.log("HybridResolver for example.eth deployed to:", exampleResolver.address);
  
  await ethRegistry.write.register([
    "example",
    deployer.account.address,
    zeroAddress, // No subregistry yet
    exampleResolver.address,
    (1n << 256n) - 1n, // ROLES.ALL
    MAX_EXPIRY,
  ]);
  console.log("Registered example.eth");
  
  await ethRegistry.write.setResolver([
    BigInt(labelhash("example")),
    exampleResolver.address,
    MAX_EXPIRY,
    0
  ]);
  console.log("Set resolver for example.eth in registry");
  
  console.log("Deploying subregistry for example.eth...");
  const exampleRegistry = await hre.viem.deployContract("PermissionedRegistry", [
    datastore.address,
    zeroAddress,
    (1n << 256n) - 1n, // ROLES.ALL
  ]);
  console.log("Example subregistry deployed to:", exampleRegistry.address);
  
  await ethRegistry.write.setSubregistry([BigInt(labelhash("example")), exampleRegistry.address]);
  console.log("Set subregistry for example.eth");
  
  const exampleEthNamehash = namehash("example.eth");
  const exampleLabelHash = labelhash("example");
  console.log("Namehash for example.eth:", exampleEthNamehash);
  
  console.log("Mapping namehash to labelHash in resolver...");
  await exampleResolver.write.mapNamehash([exampleEthNamehash, BigInt(exampleLabelHash), true]);
  console.log("Mapped namehash to labelHash");
  
  console.log("Setting address for example.eth...");
  await exampleResolver.write.setAddr([exampleEthNamehash, "0x1234567890123456789012345678901234567890"]);
  console.log("Set address for example.eth");
  
  console.log("Registering foo.example.eth...");
  
  console.log("Deploying HybridResolver for foo.example.eth...");
  const fooResolver = await deployHybridResolver(deployer, verifiableFactory, hybridResolverImpl, exampleRegistry.address);
  console.log("HybridResolver for foo.example.eth deployed to:", fooResolver.address);
  
  await exampleRegistry.write.register([
    "foo",
    deployer.account.address,
    zeroAddress, // No further subregistry
    fooResolver.address,
    (1n << 256n) - 1n, // ROLES.ALL
    MAX_EXPIRY,
  ]);
  console.log("Registered foo.example.eth");
  
  await exampleRegistry.write.setResolver([
    BigInt(labelhash("foo")),
    fooResolver.address,
    MAX_EXPIRY,
    0
  ]);
  console.log("Set resolver for foo.example.eth in registry");
  
  const fooExampleEthNamehash = namehash("foo.example.eth");
  const fooLabelHash = labelhash("foo");
  console.log("Namehash for foo.example.eth:", fooExampleEthNamehash);
  
  console.log("Mapping namehash to labelHash in resolver...");
  await fooResolver.write.mapNamehash([fooExampleEthNamehash, BigInt(fooLabelHash), true]);
  console.log("Mapped namehash to labelHash");
  
  console.log("Setting address for foo.example.eth...");
  await fooResolver.write.setAddr([fooExampleEthNamehash, "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"]);
  console.log("Set address for foo.example.eth");
  
  console.log("Registering .xyz TLD...");
  await rootRegistry.write.register([
    "xyz",
    deployer.account.address,
    zeroAddress, // No subregistry yet
    zeroAddress, // No resolver yet
    (1n << 256n) - 1n, // ROLES.ALL
    MAX_EXPIRY,
  ]);
  console.log("Registered .xyz TLD");
  
  console.log("Deploying HybridResolver for .xyz...");
  const xyzResolver = await deployHybridResolver(deployer, verifiableFactory, hybridResolverImpl, rootRegistry.address);
  console.log("HybridResolver for .xyz deployed to:", xyzResolver.address);
  
  await rootRegistry.write.setResolver([
    BigInt(labelhash("xyz")),
    xyzResolver.address,
    MAX_EXPIRY,
    0
  ]);
  console.log("Set resolver for .xyz in registry");
  
  const xyzNamehash = namehash("xyz");
  const xyzLabelHash = labelhash("xyz");
  console.log("Namehash for .xyz:", xyzNamehash);
  
  console.log("Mapping namehash to labelHash in resolver...");
  await xyzResolver.write.mapNamehash([xyzNamehash, BigInt(xyzLabelHash), true]);
  console.log("Mapped namehash to labelHash");
  
  console.log("Setting address for .xyz...");
  await xyzResolver.write.setAddr([xyzNamehash, "0x6666666666666666666666666666666666666666"]);
  console.log("Set address for .xyz");
  
  console.log("Deploying XYZRegistry...");
  const xyzRegistry = await hre.viem.deployContract("PermissionedRegistry", [
    datastore.address,
    zeroAddress,
    (1n << 256n) - 1n, // ROLES.ALL
  ]);
  console.log("XYZRegistry deployed to:", xyzRegistry.address);
  
  await rootRegistry.write.setSubregistry([BigInt(labelhash("xyz")), xyzRegistry.address]);
  console.log("Set XYZRegistry as subregistry for .xyz");
  
  console.log("Registering example.xyz...");
  await xyzRegistry.write.register([
    "example",
    deployer.account.address,
    zeroAddress, // No subregistry
    exampleResolver.address, // Use same resolver as example.eth
    (1n << 256n) - 1n, // ROLES.ALL
    MAX_EXPIRY,
  ]);
  console.log("Registered example.xyz");
  
  await xyzRegistry.write.setResolver([
    BigInt(labelhash("example")),
    exampleResolver.address,
    MAX_EXPIRY,
    0
  ]);
  console.log("Set resolver for example.xyz in registry");
  
  const exampleXyzNamehash = namehash("example.xyz");
  console.log("Namehash for example.xyz:", exampleXyzNamehash);
  
  console.log("Mapping example.xyz namehash to same labelHash as example.eth...");
  await exampleResolver.write.mapNamehash([exampleXyzNamehash, BigInt(exampleLabelHash), false]);
  console.log("Mapped example.xyz namehash to same labelHash as example.eth");
  
  console.log("Setting address for example.xyz (should be same as example.eth)...");
  // Since we're using the same labelHash, this should resolve to the same address as example.eth
  const exampleXyzAddress = await exampleResolver.read.addr([exampleXyzNamehash]);
  console.log("Address for example.xyz:", exampleXyzAddress);
  
  if (exampleXyzAddress === "0x0000000000000000000000000000000000000000") {
    console.log("Setting address for example.xyz explicitly...");
    await exampleResolver.write.setAddr([exampleXyzNamehash, "0x1234567890123456789012345678901234567890"]);
    console.log("Set address for example.xyz");
  }
  
  console.log("Deploying OwnedResolver for gas comparison...");
  const ownedResolver = await deployOwnedResolver(deployer, verifiableFactory, ownedResolverImpl);
  console.log("OwnedResolver deployed to:", ownedResolver.address);
  
  console.log("\nComparing gas costs between HybridResolver and OwnedResolver...");
  
  const testNamehash = namehash("test.eth");
  const testAddress = "0x0000000000000000000000000000000000000123";
  
  console.log("Measuring gas for HybridResolver.setAddr...");
  const hybridSetAddrGas = await measureGas(
    exampleResolver,
    "setAddr",
    [exampleEthNamehash, testAddress]
  );
  
  console.log("Measuring gas for OwnedResolver.setAddr...");
  const ownedSetAddrGas = await measureGas(
    ownedResolver,
    "setAddr",
    [testNamehash, testAddress]
  );
  
  console.log("Measuring gas for HybridResolver.addr...");
  const hybridAddrGas = await estimateReadGas(
    exampleResolver,
    "addr",
    [exampleEthNamehash]
  );
  
  console.log("Measuring gas for OwnedResolver.addr...");
  const ownedAddrGas = await estimateReadGas(
    ownedResolver,
    "addr",
    [testNamehash]
  );
  
  console.log("\nGas Cost Comparison Results:");
  console.log("----------------------------");
  console.log(`HybridResolver.setAddr: ${hybridSetAddrGas} gas`);
  console.log(`OwnedResolver.setAddr: ${ownedSetAddrGas} gas`);
  console.log(`Difference: ${hybridSetAddrGas - ownedSetAddrGas} gas (${((hybridSetAddrGas - ownedSetAddrGas) / ownedSetAddrGas * 100).toFixed(2)}%)`);
  console.log(`HybridResolver.addr: ${hybridAddrGas} gas`);
  console.log(`OwnedResolver.addr: ${ownedAddrGas} gas`);
  console.log(`Difference: ${hybridAddrGas - ownedAddrGas} gas (${((hybridAddrGas - ownedAddrGas) / ownedAddrGas * 100).toFixed(2)}%)`);
  
  console.log("\nWriting deployment addresses to .env file...");
  const envContent = `
# Deployment addresses
DEPLOYER_ADDRESS=${deployer.account.address}
REGISTRY_DATASTORE_ADDRESS=${datastore.address}
ROOT_REGISTRY_ADDRESS=${rootRegistry.address}
ETH_REGISTRY_ADDRESS=${ethRegistry.address}
XYZ_REGISTRY_ADDRESS=${xyzRegistry.address}
EXAMPLE_REGISTRY_ADDRESS=${exampleRegistry.address}
UNIVERSAL_RESOLVER_ADDRESS=${universalResolver.address}
HYBRID_RESOLVER_IMPLEMENTATION=${hybridResolverImpl.address}
OWNED_RESOLVER_IMPLEMENTATION=${ownedResolverImpl.address}
EXAMPLE_RESOLVER_ADDRESS=${exampleResolver.address}
FOO_RESOLVER_ADDRESS=${fooResolver.address}
OWNED_RESOLVER_ADDRESS=${ownedResolver.address}
`;
  
  fs.writeFileSync('.env', envContent);
  console.log("Deployment addresses written to .env file");
  
  console.log("\nDeployment complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

export default main;
