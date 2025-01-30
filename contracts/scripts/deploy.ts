import { HardhatRuntimeEnvironment } from "hardhat/types";
import "@nomicfoundation/hardhat-viem";
import { keccak256, stringToHex } from "viem";
import fs from "fs/promises";

// @ts-ignore - Hardhat runtime environment will be injected
const hre: HardhatRuntimeEnvironment = global.hre;

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

  // Save addresses to .env file
  await updateEnvFile({
    DATASTORE_ADDRESS: datastore.address,
    ROOT_REGISTRY_ADDRESS: rootRegistry.address,
    ETH_REGISTRY_ADDRESS: ethRegistry.address,
    UNIVERSAL_RESOLVER_ADDRESS: universalResolver.address,
  });

  console.log("\nDeployment complete! Contract addresses:");
  console.log("RegistryDatastore:", datastore.address);
  console.log("RootRegistry:", rootRegistry.address);
  console.log("ETHRegistry:", ethRegistry.address);
  console.log("UniversalResolver:", universalResolver.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 