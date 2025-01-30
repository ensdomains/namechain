import { HardhatRuntimeEnvironment } from "hardhat/types";
import "@nomicfoundation/hardhat-viem";
import { Log, formatLog } from "viem";
import fs from "fs/promises";
import path from "path";
import dotenv from "dotenv";

// Load .env file
const ENV_FILE_PATH = path.resolve(process.cwd(), '.env');
dotenv.config({ path: ENV_FILE_PATH });

// @ts-ignore - Hardhat runtime environment will be injected
const hre: HardhatRuntimeEnvironment = global.hre;

async function formatAndPrintLog(log: Log, contractName: string) {
  const formatted = formatLog(log);
  console.log("\nEvent detected from", contractName);
  console.log("Event:", formatted.eventName);
  console.log("Args:", formatted.args);
  console.log("Block:", log.blockNumber);
  console.log("Transaction:", log.transactionHash);
  console.log("Contract Address:", log.address);
  console.log("-------------------");
}

interface ContractInfo {
  name: string;
  address: string;
  contract: any;
}

async function getRegistryContracts(): Promise<ContractInfo[]> {
  // Debug: Print environment info
  console.log("Environment file path:", ENV_FILE_PATH);
  console.log("Current working directory:", process.cwd());
  console.log("Available environment variables:", Object.keys(process.env));

  // Read environment variables for contract addresses
  const contracts: ContractInfo[] = [];
  const envVars = {
    DATASTORE_ADDRESS: "RegistryDatastore",
    ROOT_REGISTRY_ADDRESS: "RootRegistry",
    ETH_REGISTRY_ADDRESS: "ETHRegistry",
    UNIVERSAL_RESOLVER_ADDRESS: "UniversalResolver"
  };

  // Debug: Print all relevant env vars
  for (const [envVar, contractName] of Object.entries(envVars)) {
    console.log(`Checking ${envVar}:`, process.env[envVar]);
  }

  for (const [envVar, contractName] of Object.entries(envVars)) {
    const address = process.env[envVar];
    if (!address) {
      console.warn(`Warning: ${envVar} not found in ${ENV_FILE_PATH}`);
      continue;
    }

    try {
      const contract = await hre.viem.getContractAt(contractName, address);
      contracts.push({
        name: contractName,
        address,
        contract
      });
    } catch (error) {
      console.warn(`Warning: Failed to load contract ${contractName} at ${address}:`, error);
    }
  }

  if (contracts.length === 0) {
    // Try to read .env file directly
    try {
      const envContent = await fs.readFile(ENV_FILE_PATH, 'utf8');
      console.error("Content of .env file:");
      console.error(envContent);
    } catch (error) {
      console.error("Failed to read .env file directly:", error);
    }
    throw new Error(`No contract addresses found in ${ENV_FILE_PATH}`);
  }

  return contracts;
}

async function main() {
  const publicClient = await hre.viem.getPublicClient();
  
  console.log("Loading registry contracts...");
  const contracts = await getRegistryContracts();
  console.log(`Loaded ${contracts.length} contracts`);

  // Get the latest block
  const latestBlock = await publicClient.getBlockNumber();
  
  // Get historical events for all contracts
  for (const { name, address, contract } of contracts) {
    console.log(`\nFetching historical events from ${name} at ${address}...`);
    
    const logs = await publicClient.getLogs({
      address,
      fromBlock: 0n,
      toBlock: latestBlock,
      events: contract.abi.filter((x: any) => x.type === 'event')
    });

    if (logs.length === 0) {
      console.log(`No historical events found for ${name}`);
    } else {
      console.log(`Found ${logs.length} historical events for ${name}:`);
      
      // Sort logs by block number and index
      const sortedLogs = [...logs].sort((a, b) => {
        const blockDiff = Number(a.blockNumber - b.blockNumber);
        if (blockDiff !== 0) return blockDiff;
        return Number(a.logIndex - b.logIndex);
      });

      // Print all logs
      for (const log of sortedLogs) {
        await formatAndPrintLog(log, name);
      }
    }
  }

  // Watch for new events from all contracts
  console.log("\nNow watching for new events from all contracts...");
  
  const unwatchFunctions = contracts.map(({ name, address, contract }) => 
    publicClient.watchContractEvent({
      address,
      abi: contract.abi,
      onLogs: (logs: Log[]) => {
        logs.forEach(log => formatAndPrintLog(log, name));
      },
    })
  );

  // Keep the script running
  process.on('SIGINT', () => {
    console.log('Stopping event listeners...');
    unwatchFunctions.forEach(unwatch => unwatch());
    process.exit();
  });
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
}); 