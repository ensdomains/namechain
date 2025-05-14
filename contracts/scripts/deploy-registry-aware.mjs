import hre from "hardhat";
import fs from "fs";
import dotenv from "dotenv";
import {
  labelhash,
  encodeFunctionData,
  parseEventLogs,
  zeroAddress,
  namehash,
  keccak256,
  toHex,
  stringToBytes,
} from "viem";
dotenv.config();

// Define roles and flags similar to deployV2Fixture.ts
const MAX_EXPIRY = (1n << 64n) - 1n; // see: DatastoreUtils.sol

const FLAGS = {
  // see: RegistryRolesMixin.sol
  EAC: {
    REGISTRAR: 1n << 0n,
    RENEW: 1n << 1n,
    SET_SUBREGISTRY: 1n << 2n,
    SET_RESOLVER: 1n << 3n,
    SET_TOKEN_OBSERVER: 1n << 4n,
  },
  // see: L2/ETHRegistry.sol
  ETH: {
    SET_PRICE_ORACLE: 1n << 0n,
    SET_COMMITMENT_AGES: 1n << 1n,
  },
  // see: L2/UserRegistry.sol
  USER: {
    UPGRADE: 1n << 5n,
  },
  MASK: (1n << 128n) - 1n,
};

function mapFlags(flags, fn) {
  return Object.fromEntries(
    Object.entries(flags).map(([k, x]) => [
      k,
      typeof x === "bigint" ? fn(x) : mapFlags(x, fn),
    ]),
  );
}

const ROLES = {
  OWNER: FLAGS,
  ADMIN: mapFlags(FLAGS, (x) => x << 128n),
  ALL: (1n << 256n) - 1n, // see: EnhancedAccessControl.sol
};

async function main() {
  console.log("Deploying Registry-Aware Resolver...");

  const publicClient = await hre.viem.getPublicClient();
  const [walletClient] = await hre.viem.getWalletClients();
  console.log("Deploying with account:", walletClient.account.address);

  const datastore = await hre.viem.deployContract("RegistryDatastore");
  console.log("RegistryDatastore deployed to:", datastore.address);

  const rootRegistry = await hre.viem.deployContract("RootRegistry", [
    datastore.address
  ]);
  console.log("RootRegistry deployed to:", rootRegistry.address);

  const ethRegistry = await hre.viem.deployContract("PermissionedRegistry", [
    datastore.address,
    zeroAddress,
    ROLES.ALL,
  ]);
  console.log("ETHRegistry deployed to:", ethRegistry.address);

  const xyzRegistry = await hre.viem.deployContract("PermissionedRegistry", [
    datastore.address,
    zeroAddress,
    ROLES.ALL,
  ]);
  console.log("XYZRegistry deployed to:", xyzRegistry.address);

  const verifiableFactory = await hre.viem.deployContract(
    "VerifiableFactory"
  );
  console.log("VerifiableFactory deployed to:", verifiableFactory.address);

  const resolverImplementation = await hre.viem.deployContract("RegistryAwareResolver");
  console.log("RegistryAwareResolver implementation deployed to:", resolverImplementation.address);

  const ownedResolverImplementation = await hre.viem.deployContract("OwnedResolver");
  console.log("OwnedResolver implementation deployed to:", ownedResolverImplementation.address);

  const ethLabel = "eth";
  const ethLabelHash = keccak256(stringToBytes(ethLabel));
  await rootRegistry.write.register([
    ethLabel,
    walletClient.account.address,
    ethRegistry.address,
    zeroAddress,
    ROLES.ALL,
    MAX_EXPIRY,
  ]);
  console.log("Registered .eth in root registry");

  const xyzLabel = "xyz";
  const xyzLabelHash = keccak256(stringToBytes(xyzLabel));
  await rootRegistry.write.register([
    xyzLabel,
    walletClient.account.address,
    xyzRegistry.address,
    zeroAddress,
    ROLES.ALL,
    MAX_EXPIRY,
  ]);
  console.log("Registered .xyz in root registry");

  const ethResolverSalt = keccak256(stringToBytes("eth-resolver"));
  const ethResolverInitData = encodeFunctionData({
    abi: resolverImplementation.abi,
    functionName: "initialize",
    args: [walletClient.account.address, ethRegistry.address],
  });
  
  // Deploy ETH resolver proxy
  const ethResolverTxHash = await verifiableFactory.write.deployProxy([
    resolverImplementation.address,
    ethResolverSalt,
    ethResolverInitData
  ]);
  
  const ethResolverReceipt = await publicClient.getTransactionReceipt({
    hash: ethResolverTxHash,
  });
  
  const [ethResolverLog] = parseEventLogs({
    abi: verifiableFactory.abi,
    eventName: "ProxyDeployed",
    logs: ethResolverReceipt.logs,
  });
  
  const ethResolverAddress = ethResolverLog.args.proxyAddress;
  console.log("ETH Resolver deployed to:", ethResolverAddress);

  const xyzResolverSalt = keccak256(stringToBytes("xyz-resolver"));
  const xyzResolverInitData = encodeFunctionData({
    abi: resolverImplementation.abi,
    functionName: "initialize",
    args: [walletClient.account.address, xyzRegistry.address],
  });
  
  // Deploy XYZ resolver proxy
  const xyzResolverTxHash = await verifiableFactory.write.deployProxy([
    resolverImplementation.address,
    xyzResolverSalt,
    xyzResolverInitData
  ]);
  
  const xyzResolverReceipt = await publicClient.getTransactionReceipt({
    hash: xyzResolverTxHash,
  });
  
  const [xyzResolverLog] = parseEventLogs({
    abi: verifiableFactory.abi,
    eventName: "ProxyDeployed",
    logs: xyzResolverReceipt.logs,
  });
  
  const xyzResolverAddress = xyzResolverLog.args.proxyAddress;
  console.log("XYZ Resolver deployed to:", xyzResolverAddress);

  // Set resolvers for TLDs
  const [ethTokenId] = await rootRegistry.read.getNameData([ethLabel]);
  await rootRegistry.write.setResolver([ethTokenId, ethResolverAddress]);
  console.log("Set resolver for .eth");
  
  const [xyzTokenId] = await rootRegistry.read.getNameData([xyzLabel]);
  await rootRegistry.write.setResolver([xyzTokenId, xyzResolverAddress]);
  console.log("Set resolver for .xyz");

  const ethResolver = await hre.viem.getContractAt("RegistryAwareResolver", ethResolverAddress);
  const xyzResolver = await hre.viem.getContractAt("RegistryAwareResolver", xyzResolverAddress);

  const exampleRegistry = await hre.viem.deployContract("PermissionedRegistry", [
    datastore.address,
    zeroAddress,
    ROLES.ALL,
  ]);
  console.log("Example Registry deployed to:", exampleRegistry.address);

  const exampleLabel = "example";
  
  // Register example.eth in ETH registry
  await ethRegistry.write.register([
    exampleLabel,
    walletClient.account.address,
    exampleRegistry.address,
    zeroAddress,
    ROLES.ALL,
    MAX_EXPIRY,
  ]);
  console.log("Registered example.eth in ETH registry");

  // Register example.xyz in XYZ registry (pointing to the same subregistry)
  await xyzRegistry.write.register([
    exampleLabel,
    walletClient.account.address,
    exampleRegistry.address,
    zeroAddress,
    ROLES.ALL,
    MAX_EXPIRY,
  ]);
  console.log("Registered example.xyz in XYZ registry (pointing to the same subregistry)");

  const exampleResolverSalt = keccak256(stringToBytes("example-resolver"));
  const exampleResolverInitData = encodeFunctionData({
    abi: resolverImplementation.abi,
    functionName: "initialize",
    args: [walletClient.account.address, exampleRegistry.address],
  });
  
  // Deploy Example resolver proxy
  const exampleResolverTxHash = await verifiableFactory.write.deployProxy([
    resolverImplementation.address,
    exampleResolverSalt,
    exampleResolverInitData
  ]);
  
  const exampleResolverReceipt = await publicClient.getTransactionReceipt({
    hash: exampleResolverTxHash,
  });
  
  const [exampleResolverLog] = parseEventLogs({
    abi: verifiableFactory.abi,
    eventName: "ProxyDeployed",
    logs: exampleResolverReceipt.logs,
  });
  
  const exampleResolverAddress = exampleResolverLog.args.proxyAddress;
  console.log("Example Resolver deployed to:", exampleResolverAddress);

  // Set resolver for example.eth/example.xyz
  const [exampleTokenId] = await exampleRegistry.read.getNameData([exampleLabel]);
  await exampleRegistry.write.setResolver([exampleTokenId, exampleResolverAddress]);
  console.log("Set resolver for example.eth/example.xyz");

  const exampleResolver = await hre.viem.getContractAt("RegistryAwareResolver", exampleResolverAddress);

  const namehashEth = namehash("eth");
  const namehashXyz = namehash("xyz");
  const namehashExampleEth = namehash("example.eth");
  const namehashExampleXyz = namehash("example.xyz");

  await ethResolver.write.setAddr([namehashEth, "0x5555555555555555555555555555555555555555"]);
  console.log("Set ETH address for .eth");
  await xyzResolver.write.setAddr([namehashXyz, "0x6666666666666666666666666666666666666666"]);
  console.log("Set ETH address for .xyz");
  await exampleResolver.write.setAddr([namehashExampleEth, "0x1234567890123456789012345678901234567890"]);
  console.log("Set ETH address for example.eth");

  const fooRegistry = await hre.viem.deployContract("PermissionedRegistry", [
    datastore.address,
    zeroAddress,
    ROLES.ALL,
  ]);
  console.log("Foo Registry deployed to:", fooRegistry.address);

  const fooLabel = "foo";
  
  // Register foo.example.eth in example registry
  await exampleRegistry.write.register([
    fooLabel,
    walletClient.account.address,
    fooRegistry.address,
    zeroAddress,
    ROLES.ALL,
    MAX_EXPIRY,
  ]);
  console.log("Registered foo.example.eth in example registry");

  const fooResolverSalt = keccak256(stringToBytes("foo-resolver"));
  const fooResolverInitData = encodeFunctionData({
    abi: resolverImplementation.abi,
    functionName: "initialize",
    args: [walletClient.account.address, fooRegistry.address],
  });
  
  // Deploy Foo resolver proxy
  const fooResolverTxHash = await verifiableFactory.write.deployProxy([
    resolverImplementation.address,
    fooResolverSalt,
    fooResolverInitData
  ]);
  
  const fooResolverReceipt = await publicClient.getTransactionReceipt({
    hash: fooResolverTxHash,
  });
  
  const [fooResolverLog] = parseEventLogs({
    abi: verifiableFactory.abi,
    eventName: "ProxyDeployed",
    logs: fooResolverReceipt.logs,
  });
  
  const fooResolverAddress = fooResolverLog.args.proxyAddress;
  console.log("Foo Resolver deployed to:", fooResolverAddress);

  // Set resolver for foo.example.eth
  const [fooTokenId] = await fooRegistry.read.getNameData([fooLabel]);
  await fooRegistry.write.setResolver([fooTokenId, fooResolverAddress]);
  console.log("Set resolver for foo.example.eth");

  const fooResolver = await hre.viem.getContractAt("RegistryAwareResolver", fooResolverAddress);

  const namehashFooExampleEth = namehash("foo.example.eth");

  await fooResolver.write.setAddr([namehashFooExampleEth, "0xabcdefabcdefabcdefabcdefabcdefabcdefabcd"]);
  console.log("Set ETH address for foo.example.eth");

  console.log("\nMeasuring gas costs...");

  // Deploy OwnedResolver for comparison
  const ownedResolverSalt = keccak256(stringToBytes("owned-resolver"));
  const ownedResolverInitData = encodeFunctionData({
    abi: ownedResolverImplementation.abi,
    functionName: "initialize",
    args: [walletClient.account.address],
  });
  
  // Deploy OwnedResolver proxy
  const ownedResolverTxHash = await verifiableFactory.write.deployProxy([
    ownedResolverImplementation.address,
    ownedResolverSalt,
    ownedResolverInitData
  ]);
  
  const ownedResolverReceipt = await publicClient.getTransactionReceipt({
    hash: ownedResolverTxHash,
  });
  
  const [ownedResolverLog] = parseEventLogs({
    abi: verifiableFactory.abi,
    eventName: "ProxyDeployed",
    logs: ownedResolverReceipt.logs,
  });
  
  const ownedResolverAddress = ownedResolverLog.args.proxyAddress;
  console.log("OwnedResolver deployed to:", ownedResolverAddress);

  const ownedResolver = await hre.viem.getContractAt("OwnedResolver", ownedResolverAddress);

  // Measure gas for RegistryAwareResolver setAddr
  const setAddrTxHash = await exampleResolver.write.setAddr([
    namehashExampleEth, 
    "0x1234567890123456789012345678901234567890"
  ]);
  
  const setAddrReceipt = await publicClient.getTransactionReceipt({
    hash: setAddrTxHash,
  });
  
  console.log(`Gas used for setAddr with RegistryAwareResolver: ${setAddrReceipt.gasUsed.toString()}`);

  // Measure gas for OwnedResolver setAddr
  const setAddrOwnedTxHash = await ownedResolver.write.setAddr([
    namehashExampleEth, 
    "0x1234567890123456789012345678901234567890"
  ]);
  
  const setAddrOwnedReceipt = await publicClient.getTransactionReceipt({
    hash: setAddrOwnedTxHash,
  });
  
  console.log(`Gas used for setAddr with OwnedResolver: ${setAddrOwnedReceipt.gasUsed.toString()}`);

  // Estimate gas for read operations
  const getAddrGas = await publicClient.estimateContractGas({
    address: exampleResolverAddress,
    abi: exampleResolver.abi,
    functionName: "addr",
    args: [namehashExampleEth],
    account: walletClient.account,
  });
  
  console.log(`Gas used for addr with RegistryAwareResolver: ${getAddrGas.toString()}`);

  const getAddrOwnedGas = await publicClient.estimateContractGas({
    address: ownedResolverAddress,
    abi: ownedResolver.abi,
    functionName: "addr",
    args: [namehashExampleEth],
    account: walletClient.account,
  });
  
  console.log(`Gas used for addr with OwnedResolver: ${getAddrOwnedGas.toString()}`);

  // Calculate gas savings/costs
  const setAddrSavings = ((Number(setAddrOwnedReceipt.gasUsed) - Number(setAddrReceipt.gasUsed)) / Number(setAddrOwnedReceipt.gasUsed)) * 100;
  const getAddrCost = ((Number(getAddrGas) - Number(getAddrOwnedGas)) / Number(getAddrOwnedGas)) * 100;
  
  console.log(`\nRegistryAwareResolver uses ${setAddrSavings.toFixed(2)}% ${setAddrSavings > 0 ? "less" : "more"} gas for write operations (setAddr)`);
  console.log(`RegistryAwareResolver uses ${Math.abs(getAddrCost).toFixed(2)}% ${getAddrCost > 0 ? "more" : "less"} gas for read operations (addr)`);

  // Write deployment addresses to .env file
  const envContent = `
DATASTORE_ADDRESS=${datastore.address}
ROOT_REGISTRY_ADDRESS=${rootRegistry.address}
ETH_REGISTRY_ADDRESS=${ethRegistry.address}
XYZ_REGISTRY_ADDRESS=${xyzRegistry.address}
EXAMPLE_REGISTRY_ADDRESS=${exampleRegistry.address}
FOO_REGISTRY_ADDRESS=${fooRegistry.address}
ETH_RESOLVER_ADDRESS=${ethResolverAddress}
XYZ_RESOLVER_ADDRESS=${xyzResolverAddress}
EXAMPLE_RESOLVER_ADDRESS=${exampleResolverAddress}
FOO_RESOLVER_ADDRESS=${fooResolverAddress}
OWNED_RESOLVER_ADDRESS=${ownedResolverAddress}
`;

  fs.writeFileSync(".env", envContent);
  console.log("\nDeployment addresses written to .env file");
}

try {
  await main();
  process.exit(0);
} catch (error) {
  console.error(error);
  process.exit(1);
}
