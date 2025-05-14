// Simple test script to verify hardhat imports in ES modules
import hre from 'hardhat';

async function main() {
  console.log("HRE object keys:", Object.keys(hre));
  
  // Try to access viem directly from hre
  if (hre.viem) {
    console.log("hre.viem exists");
    
    try {
      // Get wallet clients (signers)
      const [walletClient] = await hre.viem.getWalletClients();
      console.log("Successfully got wallet client:", walletClient.account.address);
      
      // Get public client
      const publicClient = await hre.viem.getPublicClient();
      console.log("Successfully got public client");
      
      // Test deploying a simple contract
      console.log("Testing contract deployment...");
      try {
        const testContract = await hre.viem.deployContract("RegistryDatastore");
        console.log("Successfully deployed contract to:", testContract.address);
      } catch (error) {
        console.error("Error deploying contract:", error.message);
      }
    } catch (error) {
      console.error("Error using viem:", error.message);
    }
  } else {
    console.log("hre.viem does not exist");
  }
}

try {
  await main();
  process.exit(0);
} catch (error) {
  console.error("Unhandled error:", error);
  process.exit(1);
}
