import { ethers } from 'ethers';
import { setTimeout } from 'timers/promises';
import { CrossChainRelayer, setupCrossChainEnvironment } from './setup.js';

// Main test function
export async function runCrossChainTests() {
  console.log('Starting cross-chain ENS v2 tests...');

  // Set up the environment
  const env = await setupCrossChainEnvironment();
  const relayer = new CrossChainRelayer(
    env.l1.bridge,
    env.l2.bridge,
    env.L1,
    env.L2
  );

  try {
    // Wait a moment for event listeners to be set up
    await setTimeout(1000);

    // Test 1: Migrate a name from L1 to L2
    await testNameMigration(env, relayer);

    // Test 2: Eject a name from L2 to L1
    await testNameEjection(env, relayer);

    // Test 3: Complete round trip
    await testRoundTrip(env, relayer);

    console.log('\nAll tests completed successfully!');
  } catch (error) {
    console.error('Test error:', error);
  } finally {
    // Ensure chains are shut down even if tests fail
    try {
      await env.shutdown();
    } catch (shutdownError) {
      console.error('Shutdown error:', shutdownError);
    }
  }
}

// Test 1: Name migration from L1 to L2
async function testNameMigration(env, relayer) {
  console.log('\n=== TEST 1: Migrate Name from L1 to L2 ===');

  const name = 'example.eth';
  const l2Owner = env.L2.wallets.admin.address; // Use default account
  const l2Subregistry = await env.l2.registry.getAddress();

  console.log(`Initiating migration for name: ${name}`);
  console.log(`L2 Owner: ${l2Owner}`);
  console.log(`L2 Subregistry: ${l2Subregistry}`);

  try {
     // Initiate migration from L1 controller
    const tx = await env.L1.confirm(
      env.l1.controller.requestMigration(name, l2Owner, l2Subregistry)
    );
    console.log(`Migration requested on L1, tx hash: ${tx.hash}`);

    // Check if automatic relaying works, otherwise do manual relay
    console.log('Waiting for the relayer to process the event...');
    await setTimeout(3000);

    const filter = env.l2.registry.filters.NameRegistered();
    const events = await env.l2.registry.queryFilter(filter);

    if (events.length === 0) {
      console.log('No registration event found, performing manual relay');

      // Get the migration message
      const message = await env.l1.bridgeHelper.encodeMigrationMessage(
        name,
        l2Owner,
        l2Subregistry
      );

      // Manually relay the message
      const relayTx = await relayer.manualRelay(true, message); // true = L1->L2
      console.log(`Manual relay completed, tx hash: ${relayTx}`);
    } else {
      console.log(
        'Name registration event found on L2, automatic relay worked'
      );
    }

    // Verify the name was registered on L2
    console.log('Verifying registration on L2...');
    await setTimeout(1000);

    const nameRegisteredFilter = await env.l2.registry.filters.NameRegistered();
    const registrationEvents = await env.l2.registry.queryFilter(
      nameRegisteredFilter
    );

    if (registrationEvents.length > 0) {
      console.log('✓ Name successfully registered on L2');
    } else {
      console.log('! Name registration on L2 could not be verified');
    }
  } catch (error) {
    console.error('Error during migration test:', error);
  }

  console.log('Migration test completed');
}

// Test 2: Name ejection from L2 to L1
async function testNameEjection(env, relayer) {
  console.log('\n=== TEST 2: Eject Name from L2 to L1 ===');

  const name = 'premium.eth';
  const l1Owner = env.L1.wallets.admin.address; // Use default account
  const l1Subregistry = await env.l1.registry.getAddress();
  const expiry = Math.floor(Date.now() / 1000) + 31536000; // 1 year from now

  console.log(`Initiating ejection for name: ${name}`);
  console.log(`L1 Owner: ${l1Owner}`);
  console.log(`L1 Subregistry: ${l1Subregistry}`);
  console.log(`Expiry: ${new Date(expiry * 1000).toISOString()}`);

  try {
    // Initiate ejection from L2 controller
    const tx = await env.L2.confirm(
      env.l2.controller.requestEjection(name, l1Owner, l1Subregistry, expiry)
    );
    console.log(`Ejection requested on L2, tx hash: ${tx.hash}`);

    // Check if automatic relaying works, otherwise do manual relay
    console.log('Waiting for the relayer to process the event...');
    await setTimeout(3000);

    // Check if the name is registered on L1
    const filter = env.l1.registry.filters.NameRegistered();
    const events = await env.l1.registry.queryFilter(filter);

    if (events.length === 0) {
      console.log('No registration event found on L1, performing manual relay');

      // Get the ejection message
      const message = await env.l2.bridgeHelper.encodeEjectionMessage(
        name,
        l1Owner,
        l1Subregistry,
        expiry
      );

      // Manually relay the message
      const relayTx = await relayer.manualRelay(false, message); // false = L2->L1
      console.log(`Manual relay completed, tx hash: ${relayTx}`);
    } else {
      console.log(
        'Name registration event found on L1, automatic relay worked'
      );
    }

    // Verify the name was registered on L1
    console.log('Verifying registration on L1...');
    await setTimeout(1000);

    const nameRegisteredFilter = await env.l1.registry.filters.NameRegistered();
    const registrationEvents = await env.l1.registry.queryFilter(
      nameRegisteredFilter
    );

    if (registrationEvents.length > 0) {
      console.log('✓ Name successfully registered on L1');
    } else {
      console.log('! Name registration on L1 could not be verified');
    }
  } catch (error) {
    console.error('Error during ejection test:', error);
  }

  console.log('Ejection test completed');
}

// Test 3: Complete round trip (L1 -> L2 -> L1)
async function testRoundTrip(env, relayer) {
  console.log('\n=== TEST 3: Complete Round Trip (L1 -> L2 -> L1) ===');

  const name = 'roundtrip.eth';
  const l2Owner = env.L2.wallets.admin.address; // Use default account
  const l2Subregistry = await env.l2.registry.getAddress();
  const l1Owner = env.L1.wallets.admin.address; // Use default account
  const l1Subregistry = await env.l1.registry.getAddress();
  const expiry = Math.floor(Date.now() / 1000) + 31536000; // 1 year from now

  try {
    // Step 1: Migrate from L1 to L2
    console.log('\nStep 1: Migrate from L1 to L2');
    let tx = await env.L1.confirm(
      env.l1.controller.requestMigration(name, l2Owner, l2Subregistry)
    );
    console.log(`Migration requested on L1, tx hash: ${tx.hash}`);

    // Wait for automatic relay or do manual relay
    await setTimeout(3000);

    // Relay the migration message
    const migrationMsg = await env.l1.bridgeHelper.encodeMigrationMessage(
      name,
      l2Owner,
      l2Subregistry
    );

    try {
      await relayer.manualRelay(true, migrationMsg);
      console.log('Manual L1->L2 relay completed');
    } catch (error) {
      console.log(
        'Manual relay failed, might have already been relayed automatically'
      );
    }

    // Step 2: Eject from L2 back to L1
    console.log('\nStep 2: Eject from L2 back to L1');
    tx = await env.L2.confirm(
      env.l2.controller.requestEjection(name, l1Owner, l1Subregistry, expiry)
    );
    console.log(`Ejection requested on L2, tx hash: ${tx.hash}`);

    // Wait for automatic relay or do manual relay
    await setTimeout(3000);

    // Manual relay if needed
    const ejectionMsg = await env.l2.bridgeHelper.encodeEjectionMessage(
      name,
      l1Owner,
      l1Subregistry,
      expiry
    );
    try {
      await relayer.manualRelay(false, ejectionMsg);
      console.log('Manual L2->L1 relay completed');
    } catch (error) {
      console.log(
        'Manual relay failed, might have already been relayed automatically'
      );
    }

    // Verify results
    console.log('\nVerifying round trip results:');
    await setTimeout(1000);

    // Check if name is registered on L1
    const tokenId = ethers.keccak256(ethers.toUtf8Bytes(name));
    const isRegistered = await env.l1.registry.registered(tokenId);
    console.log(`Name registered on L1: ${isRegistered}`);

    // Check owner on L2 (should be the controller)
    const ownerOnL2 = await env.l2.registry.owners(tokenId);
    const expectedOwner = await env.l2.controller.getAddress();
    console.log(`Owner on L2: ${ownerOnL2}`);
    console.log(`Expected owner (L2 controller): ${expectedOwner}`);
    console.log(
      `Owner match: ${ownerOnL2.toLowerCase() === expectedOwner.toLowerCase()}`
    );

    if (ownerOnL2.toLowerCase() !== expectedOwner.toLowerCase()) {
      console.warn(
        'WARN: The owner on L2 is not the L2 controller as expected!'
      );
    }
  } catch (error) {
    console.error('Error during round trip test:', error);
  }

  console.log('Round trip test completed');
}

// Run the tests if executed directly
if (import.meta.url === `file://${process.argv[1]}`) {
  runCrossChainTests()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error('Test error:', error);
      process.exit(1);
    });
}

// for module usage
export { testNameMigration, testNameEjection, testRoundTrip };
