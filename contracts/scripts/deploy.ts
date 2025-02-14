import { HardhatRuntimeEnvironment } from "hardhat/types";
import "@nomicfoundation/hardhat-viem";
import { keccak256, stringToHex } from "viem";
import fs from "fs/promises";
import path from "path";
import { fileURLToPath } from "url";
import { ethers } from "hardhat";
import { encodeFunctionData } from "viem";
import { readFileSync } from "fs";
import { join } from "path";
console.log(1);
// @ts-ignore - Hardhat runtime environment will be injected
const hre: HardhatRuntimeEnvironment = global.hre;
console.log(1);
const __filename = fileURLToPath(import.meta.url);

const verifiableFactoryArtifact = JSON.parse(
  readFileSync(join(__dirname, "../out/VerifiableFactory.sol/VerifiableFactory.json"), "utf8")
);

async function updateEnvFile(newVars: Record<string, string>) {
  try {
    // Read existing .env file
    let envContent = "";
    try {
      envContent = await fs.readFile(".env", "utf8");
    } catch (error) {
      // File doesn't exist, start with empty content
    }

    // Parse existing variables
    const envVars = new Map(
      envContent
        .split("\n")
        .filter(line => line.trim() && !line.startsWith("#"))
        .map(line => line.split("=", 2) as [string, string])
    );

    // Update with new variables
    Object.entries(newVars).forEach(([key, value]) => {
      envVars.set(key, value);
    });

    // Write back to file
    const newContent = Array.from(envVars.entries())
      .map(([key, value]) => `${key}=${value}`)
      .join("\n");

    await fs.writeFile(".env", newContent + "\n");
    console.log("Updated .env file with contract addresses");
  } catch (error) {
    console.error("Failed to update .env file:", error);
  }
}


async function main() {
  console.log("Deploying ENS contracts...");

  // Get deployer account
  const [deployer] = await hre.viem.getWalletClients();
  console.log("Deploying from:", deployer.account.address);

  // Deploy RegistryDatastore
  console.log("\nDeploying RegistryDatastore...");
  const datastore = await hre.viem.deployContract("RegistryDatastore", []);
  console.log("RegistryDatastore deployed to:", datastore.address);

  // Deploy RootRegistry
  console.log("\nDeploying RootRegistry...");
  const rootRegistry = await hre.viem.deployContract("RootRegistry", [
    datastore.address,
  ]);
  console.log("RootRegistry deployed to:", rootRegistry.address);

  // Deploy ETHRegistry
  console.log("\nDeploying ETHRegistry...");
  const ethRegistry = await hre.viem.deployContract("ETHRegistry", [
    datastore.address,
  ]);
  console.log("ETHRegistry deployed to:", ethRegistry.address);

  // Deploy UniversalResolver
  console.log("\nDeploying UniversalResolver...");
  const universalResolver = await hre.viem.deployContract("UniversalResolver", [
    rootRegistry.address,
  ]);
  console.log("UniversalResolver deployed to:", universalResolver.address);

  // Deploy OwnedResolver implementation
  console.log("\nDeploying OwnedResolver...");
  const resolverImplementation = await hre.viem.deployContract("OwnedResolver", []);
  console.log("OwnedResolver implementation deployed to:", resolverImplementation.address);

  // Deploy VerifiableFactory
  console.log("\nDeploying VerifiableFactory...");
  const verifiableFactory = await hre.viem.deployContract({
    abi: verifiableFactoryArtifact.abi,
    bytecode: verifiableFactoryArtifact.bytecode
  });
  console.log("VerifiableFactory deployed to:", verifiableFactory.address);
  // Deploy resolver proxy
  const initData = encodeFunctionData({
    abi:resolverImplementation.abi,
    functionName:"initialize",
    args:[deployer.account.address]
  });
  console.log(2, initData);
  const SALT = 12345n;
  console.log("\nDeploying OwnedResolver proxy...");
  const deployTx = await verifiableFactory.write.deployProxy([
    resolverImplementation.address,
    SALT,
    initData
  ]);
  const events = await verifiableFactory.getEvents.ProxyDeployed();

  // Get proxy address from event
  const publicClient = await hre.viem.getPublicClient();
  await publicClient.waitForTransactionReceipt({ hash: deployTx });
  
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
    ethRegistry.address,
    1n,
    "https://example.com/"
  ]);
  console.log(".eth TLD minted");


  // Register test.eth
  console.log("\nRegistering test.eth...");
  const testName = "test";
  const expires = BigInt(Math.floor(Date.now() / 1000) + 31536000); // 1 year from now
  console.log(31, testName, deployer.account.address, ethRegistry.address, expires);
  await ethRegistry.write.register([
    testName,
    deployer.account.address,
    ethRegistry.address,
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


  // Save addresses to .env file
  await updateEnvFile({
    DATASTORE_ADDRESS: datastore.address,
    ROOT_REGISTRY_ADDRESS: rootRegistry.address,
    ETH_REGISTRY_ADDRESS: ethRegistry.address,
    UNIVERSAL_RESOLVER_ADDRESS: universalResolver.address,
    OWNED_RESOLVER_ADDRESS: resolverAddress,
  });

  console.log("\nDeployment complete! Contract addresses:");
  console.log("RegistryDatastore:", datastore.address);
  console.log("RootRegistry:", rootRegistry.address);
  console.log("ETHRegistry:", ethRegistry.address);
  console.log("UniversalResolver:", universalResolver.address);
  console.log("OwnedResolver:", resolverAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 