// Setup script for cross-chain ENS v2 testing with Anvil
import { ethers } from 'ethers';
import fs from 'fs';
import path from 'path';
import { execSync } from 'child_process';
import { spawn } from 'child_process';

// Configuration
const L1_RPC_URL = 'http://localhost:8545';
const L2_RPC_URL = 'http://localhost:8546';

// Connect to both networks
const l1Provider = new ethers.JsonRpcProvider(L1_RPC_URL);
const l2Provider = new ethers.JsonRpcProvider(L2_RPC_URL);

// Helper to get a wallet on both chains
async function getWallets() {
  // Use the default anvil private key for the first account
  const PRIVATE_KEY = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
  
  const l1Wallet = new ethers.Wallet(PRIVATE_KEY, l1Provider);
  const l2Wallet = new ethers.Wallet(PRIVATE_KEY, l2Provider);
  
  console.log(`Using wallet address: ${l1Wallet.address}`);
  
  // Check balances
  const l1Balance = await l1Provider.getBalance(l1Wallet.address);
  const l2Balance = await l2Provider.getBalance(l2Wallet.address);
  
  console.log(`L1 Balance: ${ethers.formatEther(l1Balance)} ETH`);
  console.log(`L2 Balance: ${ethers.formatEther(l2Balance)} ETH`);
  
  return { l1Wallet, l2Wallet };
}

// Compile contracts using Forge
function compileContractsWithForge() {
  console.log('Compiling contracts with Forge...');
  try {
    // Run forge build to compile all contracts
    execSync('forge build --force', { stdio: 'inherit' });
    console.log('Compilation successful');
  } catch (error) {
    console.error('Error during compilation:', error.message);
    throw new Error('Forge compilation failed');
  }
}

// Load compiled contracts from Forge output
function loadCompiledContracts() {
  const contractNames = [
    'MockL1Registry',
    'MockL2Registry',
    'MockBridgeHelper',
    'MockL1Bridge',
    'MockL2Bridge',
    'MockL1MigrationController',
    'MockL2MigrationController'
  ];
  
  const contracts = {};
  const outDir = path.join(process.cwd(), 'out');
  
  for (const contractName of contractNames) {
    try {
      // First try to find the contract in its expected location
      let artifactPath;
      
      // Check in various possible locations
      const possiblePaths = [
        // In mocks subdirectory
        path.join(outDir, `${contractName}.sol`, `${contractName}.json`)
      ];
      
      // Find the first path that exists
      for (const possiblePath of possiblePaths) {
        if (fs.existsSync(possiblePath)) {
          artifactPath = possiblePath;
          break;
        }
      }
      
      if (!artifactPath) {
        throw new Error(`Could not find artifact for ${contractName}`);
      }
      
      const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));
      
      contracts[contractName] = {
        abi: artifact.abi,
        bytecode: artifact.bytecode.object,
      };
      
      console.log(`Loaded compiled contract: ${contractName}`);
    } catch (error) {
      console.error(`Error loading compiled contract ${contractName}:`, error.message);
      throw error;
    }
  }
  
  return contracts;
}

// Deploy a contract to a specific chain
async function deployContract(wallet, contractName, abi, bytecode, ...args) {
  console.log(wallet.provider);
  console.log(`Deploying ${contractName} to ${wallet.provider}...`);
  
  const factory = new ethers.ContractFactory(abi, bytecode, wallet);
  const contract = await factory.deploy(...args);
  
  console.log(`${contractName} deploying, waiting for deployment...`);
  await contract.waitForDeployment();
  
  const address = await contract.getAddress();
  console.log(`${contractName} deployed to: ${address}`);
  return contract;
}

// Main function to set up the testing environment
async function setupCrossChainEnvironment() {
  // Deploy the contracts
  console.log("Start chains...");
  startAnvilInstances();
  // Get wallets for both chains
  const { l1Wallet, l2Wallet } = await getWallets();
  
  // Compile contracts with Forge
  compileContractsWithForge();
  
  // Load compiled contracts
  const contracts: any = loadCompiledContracts();
  
  // Deploy the contracts
  console.log("Deploying contracts...");
  
  // First deploy registries
  const l1Registry = await deployContract(
    l1Wallet,
    'MockL1Registry',
    contracts.MockL1Registry.abi,
    contracts.MockL1Registry.bytecode
  );
  
  const l2Registry = await deployContract(
    l2Wallet,
    'MockL2Registry',
    contracts.MockL2Registry.abi,
    contracts.MockL2Registry.bytecode
  );
  
  // Deploy the helper on L1
  const bridgeHelperL1 = await deployContract(
    l1Wallet,
    'MockBridgeHelper',
    contracts.MockBridgeHelper.abi,
    contracts.MockBridgeHelper.bytecode
  );

  // Deploy the helper on L2
  const bridgeHelperL2 = await deployContract(
    l2Wallet,
    'MockBridgeHelper',
    contracts.MockBridgeHelper.abi,
    contracts.MockBridgeHelper.bytecode
  );
  
  // Deploy bridges with temporary target addresses (we'll update them later)
  const l1Bridge = await deployContract(
    l1Wallet,
    'MockL1Bridge',
    contracts.MockL1Bridge.abi,
    contracts.MockL1Bridge.bytecode,
    ethers.ZeroAddress // Ethers v6 uses ZeroAddress instead of constants.AddressZero
  );
  
  const l2Bridge = await deployContract(
    l2Wallet,
    'MockL2Bridge',
    contracts.MockL2Bridge.abi,
    contracts.MockL2Bridge.bytecode,
    ethers.ZeroAddress // Ethers v6 uses ZeroAddress instead of constants.AddressZero
  );
  
  // Deploy controllers
  const l1Controller = await deployContract(
    l1Wallet,
    'MockL1MigrationController',
    contracts.MockL1MigrationController.abi,
    contracts.MockL1MigrationController.bytecode,
    await l1Registry.getAddress(),
    await bridgeHelperL1.getAddress(),
    await l1Bridge.getAddress()
  );
  
  const l2Controller = await deployContract(
    l2Wallet,
    'MockL2MigrationController',
    contracts.MockL2MigrationController.abi,
    contracts.MockL2MigrationController.bytecode,
    await l2Registry.getAddress(),
    await bridgeHelperL2.getAddress(),
    await l2Bridge.getAddress()
  );
  
  // Update bridge target contracts
  console.log("Setting up bridge target contracts...");
  await (l1Bridge as any).setTargetContract(await l1Controller.getAddress());
  await (l2Bridge as any).setTargetContract(await l2Controller.getAddress());
  
  console.log('Cross-chain environment setup complete!');
  
  // Return all deployed contracts for use in tests or manual interactions
  return {
    l1: {
      registry: l1Registry,
      bridge: l1Bridge,
      bridgeHelper: bridgeHelperL1,
      controller: l1Controller,
      wallet: l1Wallet
    },
    l2: {
      registry: l2Registry,
      bridge: l2Bridge,
      bridgeHelper: bridgeHelperL2,
      controller: l2Controller,
      wallet: l2Wallet
    }
  };
}

function startAnvilInstances() {
  console.log('Starting L1 Anvil instance...');
  const anvilL1 = spawn('anvil', ['--port', '8545', '--chain-id', '31337'], {
    stdio: 'ignore',
    detached: true
  });
  anvilL1.unref(); // Unreference the process so it won't keep the Node.js process running
  
  console.log('Starting L2 Anvil instance...');
  const anvilL2 = spawn('anvil', ['--port', '8546', '--chain-id', '31338'], {
    stdio: 'ignore',
    detached: true
  });
  anvilL2.unref();
  
  console.log('Waiting for Anvil instances to start...');
  execSync('sleep 2');
}

// Simulate a relayer that listens for events and forwards messages
class CrossChainRelayer {
  l1Bridge: any;
  l2Bridge: any;
  l1Wallet: any;
  l2Wallet: any;
  
  constructor(l1Bridge, l2Bridge, l1Wallet, l2Wallet) {
    this.l1Bridge = l1Bridge;
    this.l2Bridge = l2Bridge;
    this.l1Wallet = l1Wallet;
    this.l2Wallet = l2Wallet;
    
    this.setupListeners();
  }
  
  setupListeners() {
    console.log("Setting up cross-chain event listeners...");
    
    // Listen for L1->L2 messages
    this.l1Bridge.on(this.l1Bridge.filters.L1ToL2Message, async (message, event) => {
      console.log(`Relaying message from L1 to L2:`);
      console.log(`Message: ${message}`);
      console.log(`Transaction: ${event.log.transactionHash}`);
      
      try {
        // Create a transaction to relay the message to L2
        const tx = await this.l2Bridge.connect(this.l2Wallet).receiveMessageFromL1(message);
        console.log('tx', tx)
        await tx.wait();
        
        console.log(`Message relayed to L2, tx hash: ${tx.hash}`);
      } catch (error) {
        console.error(`Error relaying message to L2:`, error.message);
      }
    });
    
    // Listen for L2->L1 messages
    this.l2Bridge.on(this.l2Bridge.filters.L2ToL1Message, async (message, event) => {
      console.log(`Relaying message from L2 to L1:`);
      console.log(`Message: ${message}`);
      console.log(`Transaction: ${event.log.transactionHash}`);
      
      try {
        // Create a transaction to relay the message to L1
        const tx = await this.l1Bridge.connect(this.l1Wallet).receiveMessageFromL2(message);
        await tx.wait();
        
        console.log(`Message relayed to L1, tx hash: ${tx.hash}`);
      } catch (error) {
        console.error(`Error relaying message to L1:`, error.message);
      }
    });
    
    console.log("Cross-chain event listeners set up successfully");
  }
  
  // Method to manually relay a message for testing
  async manualRelay(fromL1ToL2, message) {
    try {
      if (fromL1ToL2) {
        console.log(`Manually relaying message from L1 to L2`);
        const tx = await this.l2Bridge.connect(this.l2Wallet).receiveMessageFromL1(message);
        const receipt = await tx.wait();
        return receipt?.hash;
      } else {
        console.log(`Manually relaying message from L2 to L1`);
        const tx = await this.l1Bridge.connect(this.l1Wallet).receiveMessageFromL2(message);
        const receipt = await tx.wait();
        return receipt?.hash;
      }
    } catch (error) {
      console.error(`Error in manual relay:`, error.message);
      throw error;
    }
  }
}

  export {
    setupCrossChainEnvironment,
    CrossChainRelayer
  }
