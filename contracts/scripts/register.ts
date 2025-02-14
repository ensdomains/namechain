import { HardhatRuntimeEnvironment } from "hardhat/types";
import "@nomicfoundation/hardhat-viem";
import { keccak256, stringToHex } from "viem";
import { encodeFunctionData } from "viem";
import * as dotenv from "dotenv";

dotenv.config();

// @ts-ignore - Hardhat runtime environment will be injected
const hre: HardhatRuntimeEnvironment = global.hre;

async function main() {
  console.log("Setting up ENS contracts...");

  // Get deployer account
  const [deployer] = await hre.viem.getWalletClients();
  console.log("Using account:", deployer.account.address);

  // Get contract instances
  const datastore = await hre.viem.getContractAt("RegistryDatastore", process.env.DATASTORE_ADDRESS! as `0x${string}`);
  const rootRegistry = await hre.viem.getContractAt("RootRegistry", process.env.ROOT_REGISTRY_ADDRESS! as `0x${string}`);
  const ethRegistry = await hre.viem.getContractAt("ETHRegistry", process.env.ETH_REGISTRY_ADDRESS! as `0x${string}`);
  const universalResolver = await hre.viem.getContractAt("UniversalResolver", process.env.UNIVERSAL_RESOLVER_ADDRESS! as `0x${string}`);
  const resolverImplementation = await hre.viem.getContractAt("OwnedResolver", process.env.OWNED_RESOLVER_ADDRESS! as `0x${string}`);
  const verifiableFactory = await hre.viem.getContractAt("VerifiableFactory", process.env.VERIFIABLE_FACTORY_ADDRESS! as `0x${string}`);

  // Deploy resolver proxy
  console.log("\nDeploying OwnedResolver proxy...");
  const initData = encodeFunctionData({
    abi: resolverImplementation.abi,
    functionName: "initialize",
    args: [deployer.account.address]
  });
  console.log({abi: resolverImplementation.abi, functionName: "initialize", args: [deployer.account.address]})
  const SALT = 123456n;
  console.log("initData")
  console.log("Deploying OwnedResolver proxy...", process.env.OWNED_RESOLVER_ADDRESS, SALT, initData);
  const deployTx = await verifiableFactory.write.deployProxy([
    process.env.OWNED_RESOLVER_ADDRESS!,
    SALT,
    initData
  ]);
  

  // Get proxy address from event
  const publicClient = await hre.viem.getPublicClient();
  await publicClient.waitForTransactionReceipt({ hash: deployTx });
  const events = await verifiableFactory.getEvents.ProxyDeployed();
  const resolverAddress = events[0].args.proxyAddress;
  console.log("OwnedResolver proxy deployed to:", resolverAddress);

  // Setup roles
  console.log("\nSetting up roles...");
  await rootRegistry.write.grantRole([
    keccak256(stringToHex("TLD_ISSUER_ROLE")),
    deployer.account.address,
  ]);
  console.log("Granted TLD_ISSUER_ROLE to deployer");

  await ethRegistry.write.grantRole([
    keccak256(stringToHex("REGISTRAR_ROLE")),
    deployer.account.address,
  ]);
  console.log("Granted REGISTRAR_ROLE to deployer");

  // Mint .eth TLD
  console.log("\nMinting .eth TLD...");
  await rootRegistry.write.mint([
    "eth",
    deployer.account.address,
    process.env.ETH_REGISTRY_ADDRESS!,
    1n,
    "https://example.com/"
  ]);
  console.log(".eth TLD minted");

  // Register test.eth
  console.log("\nRegistering test.eth...");
  const testName = "test";
  const expires = BigInt(Math.floor(Date.now() / 1000) + 31536000); // 1 year from now
  await ethRegistry.write.register([
    testName,
    deployer.account.address,
    process.env.ETH_REGISTRY_ADDRESS!,
    0n,
    expires
  ]);
  console.log("test.eth registered");

  // Set resolver for test.eth
  const testLabelHash = keccak256(stringToHex(testName));
  await ethRegistry.write.setResolver([testLabelHash, resolverAddress]);
  console.log("Resolver set for test.eth");

  // Set ETH address for test.eth
  const resolver = await hre.viem.getContractAt("OwnedResolver", resolverAddress);
  await resolver.write.setAddr([
    testLabelHash,
    60n, // ETH coin type
    deployer.account.address
  ]);
  console.log("ETH address set for test.eth");

  console.log("\nSetup complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 