import { ethers } from 'ethers';
import { setTimeout } from 'timers/promises';
import { CrossChainRelayer, setupCrossChainEnvironment } from './setup.js';

function labelToCanonicalId(label: string) {
  const labelHash = ethers.keccak256(ethers.toUtf8Bytes(label));
  const id = BigInt(labelHash);
  
  return `0x${getCanonicalId(id).toString(16)}`;
}

function getCanonicalId(id: bigint) {
  const idBigInt = BigInt(id);
  const mask = BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000");
  
  return idBigInt & mask;
}

const ALL_ROLES = BigInt("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff");

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

    // Test 1: Eject a name from L2 to L1
    await testNameEjection(env, relayer);

    // Test 2: Complete round trip
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

// Test 1: Name ejection from L2 to L1
async function testNameEjection(env, relayer) {
  console.log('\n=== TEST 2: Eject Name from L2 to L1 ===');

  const label = 'premium';
  const name = 'premium.eth';
  const user = env.L2.wallets.admin.address;
  const l1Owner = env.L1.wallets.admin.address;
  const l1Subregistry = await env.l1.registry.getAddress();
  const l1Resolver = ethers.ZeroAddress;
  const expiryTime = Math.floor(Date.now() / 1000) + 31536000; // 1 year from now
  const roleBitmap = ALL_ROLES;

  console.log(`Initiating ejection for name: ${name}`);
  console.log(`L2 User: ${user}`);
  console.log(`L1 Target Owner: ${l1Owner}`);
  console.log(`L1 Target Subregistry: ${l1Subregistry}`);
  console.log(`Expiry: ${new Date(expiryTime * 1000).toISOString()}`);

  try {
    // First register the name on L2
    console.log('Registering the name on L2...');
    const registerTx = await env.L2.confirm(
      env.l2.registry.register(
        label,
        user,
        env.l2.registry.getAddress(),
        ethers.ZeroAddress,
        roleBitmap,
        expiryTime
      )
    );
    console.log(`Name registered on L2, tx hash: ${registerTx.hash}`);

    // Get the token ID
    const nameData = await env.l2.registry.getNameData(label);
    const tokenId = nameData[0]; // First element is the tokenId
    console.log(`TokenID from registry: ${tokenId}`);

    const owner = await env.l2.registry.ownerOf(tokenId);
    console.log(`Token owner: ${owner}`);

    // Get the canonical ID to verify the label matches
    const canonicalId = await env.l2.registry.getTokenIdResource(tokenId);
    console.log(`Canonical ID: ${canonicalId}`);

    const labelHash = labelToCanonicalId(label);
    console.log(`Label hash for "${label}": ${labelHash}`);
    console.log(`Token ID for "${label}": 0x${tokenId.toString(16)}`);
    console.log(`Does it match resource? ${labelHash === canonicalId}`);

    const TransferDataStruct = [
      label,
      l1Owner,
      l1Subregistry,
      l1Resolver,
      roleBitmap,
      expiryTime
    ];

    const encodedData = ethers.AbiCoder.defaultAbiCoder().encode(
      ["tuple(string,address,address,address,uint256,uint64)"],
      [TransferDataStruct]
    );

    console.log("L2 registry", await env.l2.registry.getAddress());
    console.log("L2 controller", await env.l2.controller.getAddress());

    // Transfer the token to L2EjectionController
    console.log('Transferring token to L2EjectionController...');
    const transferTx = await env.L2.confirm(
      env.l2.registry.safeTransferFrom(
        owner,
        await env.l2.controller.getAddress(),
        tokenId,
        1,
        encodedData
      )
    );
    console.log(`Token transferred to L2EjectionController, tx hash: ${transferTx.hash}`);

    // Check if automatic relaying works, otherwise do manual relay
    console.log('Waiting for the relayer to process the event...');
    await setTimeout(3000);

    // Check for NameEjected events on L1
    const ejectionFilter = env.l1.controller.filters.NameEjected();
    const ejectionEvents = await env.l1.controller.queryFilter(ejectionFilter);

    if (ejectionEvents.length === 0) {
      console.log('No NameEjected event found on L1, performing manual relay');

      // Get the last bridge message
      const messageFilter = env.l2.bridge.filters.L2ToL1Message();
      const messages = await env.l2.bridge.queryFilter(messageFilter);
      
      if (messages.length > 0) {
        const lastMessage = messages[messages.length - 1].args[0]; // Get the message bytes
        
        // Manually relay the message
        const relayTx = await relayer.manualRelay(false, lastMessage); // false = L2->L1
        console.log(`Manual relay completed, tx hash: ${relayTx}`);
      } else {
        console.log('No bridge messages found to relay');
      }
    } else {
      console.log('Name ejection event found on L1, automatic relay worked');
    }

    // Verify the name was registered on L1
    console.log('Verifying registration on L1...');
    await setTimeout(1000);

    // Verify ownership on L1
    try {
      const l1Owner = await env.l1.registry.ownerOf(tokenId);
      console.log(`Owner on L1: ${l1Owner}`);
      console.log('✓ Name successfully registered on L1');
    } catch (error) {
      console.log('! Name registration on L1 could not be verified');
      console.log(error.message);
    }
  } catch (error) {
    console.error('Error during ejection test:', error);
    throw error;
  }

  console.log('Ejection test completed');
}

// Test 2: Complete round trip (L2 -> L1 -> L2)
async function testRoundTrip(env, relayer) {
  console.log('\n=== TEST 3: Complete Round Trip (L2 -> L1 -> L2) ===');

  const label = 'roundtrip';
  const name = 'roundtrip.eth';
  const l1User = env.L1.wallets.admin.address;
  const l2User = env.L2.wallets.admin.address;
  const l2Subregistry = await env.l2.registry.getAddress();
  const l1Subregistry = await env.l1.registry.getAddress();
  const resolver = ethers.ZeroAddress;
  const expiryTime = Math.floor(Date.now() / 1000) + 31536000; // 1 year from now
  const roleBitmap = ALL_ROLES;

  try {
    // Step 1: Register on L2
    console.log('\nRegistering name on L2...');
    const registerTx = await env.L2.confirm(
      env.l2.registry.register(
        label,
        l2User,
        l2Subregistry,
        resolver,
        roleBitmap,
        expiryTime
      )
    );
    console.log(`Name registered on L2, tx hash: ${registerTx.hash}`);

    // Get the token ID
    const nameData = await env.l2.registry.getNameData(label);
    const tokenId = nameData[0]; // First element is the tokenId
    console.log(`TokenID from registry: ${tokenId}`);

    // Step 2: Eject from L2 to L1
    console.log('\nStep 2: Eject from L2 to L1');

    let TransferDataStruct = [
      label,
      l1User,
      l1Subregistry,
      resolver,
      roleBitmap,
      expiryTime
    ];

    let encodedData = ethers.AbiCoder.defaultAbiCoder().encode(
      ["tuple(string,address,address,address,uint256,uint64)"],
      [TransferDataStruct]
    );

    // Transfer the token to L2EjectionController
    const transferTxToL1 = await env.L2.confirm(
      env.l2.registry.safeTransferFrom(
        l2User,
        await env.l2.controller.getAddress(),
        tokenId,
        1,
        encodedData
      )
    );
    console.log(`Token transferred to L2EjectionController, tx hash: ${transferTxToL1.hash}`);

    // Wait for automatic relay or do manual relay
    await setTimeout(3000);

    // Check for NameEjected events on L1
    const ejectionFilter = env.l1.controller.filters.NameEjected();
    const ejectionEvents = await env.l1.controller.queryFilter(ejectionFilter);

    if (ejectionEvents.length === 0) {
      console.log('No NameEjected event found on L1, performing manual relay');

      // Get the last bridge message
      const messageFilter = env.l2.bridge.filters.L2ToL1Message();
      const messages = await env.l2.bridge.queryFilter(messageFilter);
      
      if (messages.length > 0) {
        const lastMessage = messages[messages.length - 1].args[0]; // Get the message bytes
        
        // Manually relay the message
        const relayTx = await relayer.manualRelay(false, lastMessage); // false = L2->L1
        console.log(`Manual relay completed, tx hash: ${relayTx}`);
      } else {
        console.log('No bridge messages found to relay');
      }
    } else {
      console.log('Name ejection event found on L1, automatic relay worked');
    }

    // Verify ownership on L1
    try {
      const owner = await env.l1.registry.ownerOf(tokenId);
      console.log(`Owner on L1: ${owner}`);
      console.log('✓ Name successfully registered on L1');
    } catch (error) {
      console.log('! Name registration on L1 could not be verified');
      console.log(error.message);
      // If ejection failed, we can't continue
      return;
    }
    
    // Step 3: Eject from L1 back to L2
    console.log('\nStep 3: Eject from L1 back to L2');

    TransferDataStruct = [
      label,
      l2User,
      l2Subregistry,
      resolver,
      roleBitmap,
      expiryTime
    ];

    // encode the TransferData
    encodedData = ethers.AbiCoder.defaultAbiCoder().encode(
      ["tuple(string,address,address,address,uint256,uint64)"],
      [TransferDataStruct]
    );

    // Transfer the token to L1EjectionController
    const transferTxToL2 = await env.L1.confirm(
      env.l1.registry.safeTransferFrom(
        l1User,
        await env.l1.controller.getAddress(),
        tokenId,
        1,
        encodedData
      )
    );
    console.log(`Token transferred to L1EjectionController, tx hash: ${transferTxToL2.hash}`);

    // Wait for automatic relay or do manual relay
    await setTimeout(3000);

    // Check for NameMigrated events on L2
    const migrationFilter = env.l2.controller.filters.NameMigrated();
    const migrationEvents = await env.l2.controller.queryFilter(migrationFilter);

    if (migrationEvents.length === 0) {
      console.log('No NameMigrated event found, performing manual relay');

      // Get the last bridge message
      const messageFilter = env.l1.bridge.filters.L1ToL2Message();
      const messages = await env.l1.bridge.queryFilter(messageFilter);
      
      if (messages.length > 0) {
        const lastMessage = messages[messages.length - 1].args[0]; // Get the message bytes
        
        // Manually relay the message
        const relayTx = await relayer.manualRelay(true, lastMessage); // true = L1->L2
        console.log(`Manual L1->L2 relay completed, tx hash: ${relayTx}`);
      } else {
        console.log('No bridge messages found to relay');
      }
    } else {
      console.log('Name migration event found on L2, automatic relay worked');
    }

    // Verify results
    console.log('\nVerifying round trip results:');
    await setTimeout(3000);
    
    // Verify ownership on L2 (final destination)
    try {
      const finalL2Owner = await env.l2.registry.ownerOf(tokenId);
      console.log(`Final owner on L2: ${finalL2Owner}`);
      console.log(`Expected owner: ${l2User}`);
      console.log(`Owner match: ${finalL2Owner.toLowerCase() === l2User.toLowerCase()}`);
      
      // Check for subregistry
      try {
        const subregistry = await env.l2.registry.getSubregistry(name);
        console.log(`Subregistry on L2: ${subregistry}`);
      } catch (error) {
        console.log('! Could not check subregistry on L2');
      }
    } catch (error) {
      console.log('! Failed to get owner on L2, name might not be registered');
      console.log('Error details:', error.message);
    }
  } catch (error) {
    console.error('Error during round trip test:', error);
    throw error;
  }
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
export { testNameEjection, testRoundTrip };
