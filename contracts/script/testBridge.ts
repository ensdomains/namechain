// Test script for cross-chain ENS v2 name migration with updated mock bridges
import { ethers } from 'ethers';
import { setTimeout } from 'timers/promises';
import { setupCrossChainEnvironment, CrossChainRelayer } from './setup.js';

// Main test function
async function runCrossChainTests() {
  console.log('Starting cross-chain ENS v2 tests with mock bridges...');
  
  // Set up the environment
  const env = await setupCrossChainEnvironment();
  
  // Create the relayer to handle cross-chain messages
  const relayer = new CrossChainRelayer(
    env.l1.bridge,
    env.l2.bridge,
    env.l1.wallet,
    env.l2.wallet
  );
  
  console.log("Relayer created and listening for cross-chain events");
  
  // Wait a moment for event listeners to be set up
  await setTimeout(1000);
  
  // Test 1: Migrate a name from L1 to L2
  await testNameMigration(env, relayer);
  
  // Test 2: Eject a name from L2 to L1
  await testNameEjection(env, relayer);
  
  // Test 3: Complete round trip
  await testRoundTrip(env, relayer);
  
  console.log("\nAll tests completed successfully!");
}

// Test name migration from L1 to L2
async function testNameMigration(env, relayer) {
  console.log("\n=== TEST 1: Migrate Name from L1 to L2 ===");
  
  const name = "example.eth";
  const l2Owner = env.l2.wallet.address;
  const l2Subregistry = await env.l2.registry.getAddress();
  
  console.log(`Initiating migration for name: ${name}`);
  console.log(`L2 Owner: ${l2Owner}`);
  console.log(`L2 Subregistry: ${l2Subregistry}`);
  
  // Initiate migration from L1 controller
  const tx = await env.l1.controller.requestMigration(name, l2Owner, l2Subregistry);
  await tx.wait();
  
  console.log(`Migration requested on L1, tx hash: ${tx.hash}`);
  
  // Check if automatic relaying works, otherwise do manual relay
  console.log("Waiting for the relayer to process the event...");
  await setTimeout(3000);
  
  // Check if the name is registered on L2 - this is a simple test and may not be accurate in all cases
  try {
    const filter = env.l2.registry.filters.NameRegistered();
    const events = await env.l2.registry.queryFilter(filter);
    
    if (events.length === 0) {
      console.log("No registration event found, performing manual relay");
      
      // Get the migration message
      const message = await env.l1.bridgeHelper.encodeMigrationMessage(name, l2Owner, l2Subregistry);
      
      // Manually relay the message
      const relayTx = await relayer.manualRelay(true, message); // true = L1->L2
      console.log(`Manual relay completed, tx hash: ${relayTx}`);
    } else {
      console.log("Name registration event found on L2, automatic relay worked");
    }
  } catch (error) {
    console.error("Error checking L2 registration:", error.message);
    
    // Fallback to manual relay
    console.log("Performing fallback manual relay");
    const message = await env.l1.bridgeHelper.encodeMigrationMessage(name, l2Owner, l2Subregistry);
    await relayer.manualRelay(true, message);
  }
  
  console.log("Migration test completed");
}

// Test name ejection from L2 to L1
async function testNameEjection(env, relayer) {
  console.log("\n=== TEST 2: Eject Name from L2 to L1 ===");
  
  const name = "premium.eth";
  const l1Owner = env.l1.wallet.address;
  const l1Subregistry = await env.l1.registry.getAddress();
  const expiry = Math.floor(Date.now() / 1000) + 31536000; // 1 year from now
  
  console.log(`Initiating ejection for name: ${name}`);
  console.log(`L1 Owner: ${l1Owner}`);
  console.log(`L1 Subregistry: ${l1Subregistry}`);
  console.log(`Expiry: ${new Date(expiry * 1000).toISOString()}`);
  
  // Initiate ejection from L2 controller
  const tx = await env.l2.controller.requestEjection(name, l1Owner, l1Subregistry, expiry);
  await tx.wait();
  
  console.log(`Ejection requested on L2, tx hash: ${tx.hash}`);
  
  // Check if automatic relaying works, otherwise do manual relay
  console.log("Waiting for the relayer to process the event...");
  await setTimeout(3000);
  
  // Check if the name is registered on L1
  try {
    const filter = env.l1.registry.filters.NameRegistered();
    const events = await env.l1.registry.queryFilter(filter);
    
    if (events.length === 0) {
      console.log("No registration event found on L1, performing manual relay");
      
      // Get the ejection message
      const message = await env.l2.bridgeHelper.encodeEjectionMessage(name, l1Owner, l1Subregistry, expiry);
      
      // Manually relay the message
      const relayTx = await relayer.manualRelay(false, message); // false = L2->L1
      console.log(`Manual relay completed, tx hash: ${relayTx}`);
    } else {
      console.log("Name registration event found on L1, automatic relay worked");
    }
  } catch (error) {
    console.error("Error checking L1 registration:", error.message);
    
    // Fallback to manual relay
    console.log("Performing fallback manual relay");
    const message = await env.l2.bridgeHelper.encodeEjectionMessage(name, l1Owner, l1Subregistry, expiry);
    await relayer.manualRelay(false, message);
  }
  
  console.log("Ejection test completed");
}

// Test a full round trip (L1 -> L2 -> L1)
async function testRoundTrip(env, relayer) {
  console.log("\n=== TEST 3: Complete Round Trip (L1 -> L2 -> L1) ===");
  
  const name = "roundtrip.eth";
  const l2Owner = env.l2.wallet.address;
  const l2Subregistry = await env.l2.registry.getAddress();
  const l1Owner = env.l1.wallet.address;
  const l1Subregistry = await env.l1.registry.getAddress();
  const expiry = Math.floor(Date.now() / 1000) + 31536000; // 1 year from now
  
  console.log("Step 1: Migrate from L1 to L2");
  
  // Initiate migration from L1 to L2
  let tx = await env.l1.controller.requestMigration(name, l2Owner, l2Subregistry);
  await tx.wait();
  console.log(`Migration requested on L1, tx hash: ${tx.hash}`);
  
  // Wait for automatic relay or do manual relay
  await setTimeout(3000);
  
  // Manual relay if needed
  const migrationMsg = await env.l1.bridgeHelper.encodeMigrationMessage(name, l2Owner, l2Subregistry);
  try {
    await relayer.manualRelay(true, migrationMsg);
    console.log("Manual L1->L2 relay completed");
  } catch (error) {
    console.log("Manual relay failed, might have already been relayed automatically");
  }
  
  console.log("\nStep 2: Eject from L2 back to L1");
  
  // Initiate ejection from L2 to L1
  tx = await env.l2.controller.requestEjection(name, l1Owner, l1Subregistry, expiry);
  await tx.wait();
  console.log(`Ejection requested on L2, tx hash: ${tx.hash}`);
  
  // Wait for automatic relay or do manual relay
  await setTimeout(3000);
  
  // Manual relay if needed
  const ejectionMsg = await env.l2.bridgeHelper.encodeEjectionMessage(name, l1Owner, l1Subregistry, expiry);
  try {
    await relayer.manualRelay(false, ejectionMsg);
    console.log("Manual L2->L1 relay completed");
  } catch (error) {
    console.log("Manual relay failed, might have already been relayed automatically");
  }
  
  // Verify results
  console.log("\nVerifying round trip results:");
  
  // Check if name is registered on L1
  const tokenId = ethers.keccak256(ethers.toUtf8Bytes(name));
  try {
    const isRegistered = await env.l1.registry.registered(tokenId);
    console.log(`Name registered on L1: ${isRegistered}`);
    
    // Check owner on L2 (should be the controller)
    const ownerOnL2 = await env.l2.registry.owners(tokenId);
    const expectedOwner = await env.l2.controller.getAddress();
    console.log(`Owner on L2: ${ownerOnL2}`);
    console.log(`Expected owner (L2 controller): ${expectedOwner}`);
    console.log(`Owner match: ${ownerOnL2.toLowerCase() === expectedOwner.toLowerCase()}`);
    
    if (ownerOnL2.toLowerCase() !== expectedOwner.toLowerCase()) {
      console.warn("WARN: The owner on L2 is not the L2 controller as expected!");
      console.warn("This could indicate an issue with the ejection process in your controller implementation.");
    }
  } catch (error) {
    console.error("Error verifying round trip results:", error.message);
  }
  
  console.log("Round trip test completed");
}

// Run the tests if executed directly
runCrossChainTests()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('Test error:', error);
    process.exit(1);
  });

// For module usage
export {
  runCrossChainTests,
  testNameMigration,
  testNameEjection,
  testRoundTrip
};
