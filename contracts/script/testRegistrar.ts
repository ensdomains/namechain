import { ethers } from 'ethers';
import { setTimeout } from 'timers/promises';
import { setupCrossChainEnvironment } from './setup.js';

export async function testRegistration() {
  console.log('Starting ETHRegistrar tests...');

  const env = await setupCrossChainEnvironment();

  try {
    await setTimeout(1000);

    // Test 1: Commitment and registration flow
    await testCommitmentRegistration(env);

    // Test 2: Renewal flow
    await testRenewal(env);

    console.log('\nAll ETHRegistrar tests completed successfully!');
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

/**
 * Test the commitment and registration flow using ETHRegistrar
 */
async function testCommitmentRegistration(env) {
  console.log('\n=== TEST 1: Name Commitment and Registration ===');

  const name = 'potato';
  const user = env.L2.wallets.admin.address;
  const secret = ethers.id('supersecret'); // Just a random secret
  const subregistry = await env.l2.registry.getAddress();
  const resolver = ethers.ZeroAddress;
  const duration = 31536000; // 1 year in seconds

  console.log(`Registering name: ${name}.eth`);
  console.log(`User: ${user}`);
  console.log(`Duration: ${duration / 86400} days`);

  try {
    // Step 1: Check if the name is available and valid
    console.log('\nStep 1: Checking name availability...');
    const isAvailable = await env.l2.ethRegistrar.available(name);
    const isValid = await env.l2.ethRegistrar.valid(name);
    
    console.log(`Name is available: ${isAvailable}`);
    console.log(`Name is valid: ${isValid}`);
    
    if (!isAvailable || !isValid) {
      throw new Error('Name is not available or not valid');
    }
    
    // Step 2: Calculate price
    console.log('\nStep 2: Calculating registration price...');
    const price = await env.l2.ethRegistrar.rentPrice(name, duration);
    const totalPrice = price.base + price.premium;
    
    console.log(`Base price: ${ethers.formatEther(price.base)} ETH`);
    console.log(`Premium: ${ethers.formatEther(price.premium)} ETH`);
    console.log(`Total price: ${ethers.formatEther(totalPrice)} ETH`);
    
    // Step 3: Make commitment
    console.log('\nStep 3: Making commitment...');
    const commitment = await env.l2.ethRegistrar.makeCommitment(
      name,
      user,
      secret,
      subregistry,
      resolver,
      duration
    );
    
    console.log(`Commitment: ${commitment}`);
    
    // Step 4: Submit commitment
    console.log('\nStep 4: Submitting commitment...');
    const commitTx = await env.L2.confirm(
      env.l2.ethRegistrar.commit(commitment)
    );
    
    console.log(`Commitment submitted, tx hash: ${commitTx.hash}`);
    
    // Step 5: Wait for minimum commitment age
    const minCommitmentAge = await env.l2.ethRegistrar.minCommitmentAge();
    console.log(`\nStep 5: Waiting for minimum commitment age (${minCommitmentAge} seconds)...`);
    
    // Wait for the minimum commitment age plus a small buffer
    const waitTime = Number(minCommitmentAge) * 1000 + 1000;
    await setTimeout(waitTime);
    
    console.log('Minimum commitment age reached');
    
    // Step 6: Register the name
    console.log('\nStep 6: Registering the name...');
    const registerTx = await env.L2.confirm(
      env.l2.ethRegistrar.register(
        name,
        user,
        secret,
        subregistry,
        resolver,
        duration,
        { value: totalPrice + ethers.parseEther('0.01') } // Add a little extra to ensure it goes through
      )
    );
    
    console.log(`Name registered, tx hash: ${registerTx.hash}`);
    
    // Step 7: Verify registration
    console.log('\nStep 7: Verifying registration...');
    
    // Get the name data from the registry
    const nameData = await env.l2.registry.getNameData(name);
    const tokenId = nameData[0]; // First element is the tokenId
    
    console.log(`TokenID: ${tokenId}`);
    
    // Check name availability after registration
    const isStillAvailable = await env.l2.ethRegistrar.available(name);
    console.log(`Name is still available: ${isStillAvailable}`);
    
    // Verify the token owner
    const owner = await env.l2.registry.ownerOf(tokenId);
    console.log(`Token owner: ${owner}`);
    console.log(`Owner match: ${owner.toLowerCase() === user.toLowerCase()}`);
    
    if (owner.toLowerCase() !== user.toLowerCase()) {
      throw new Error('Name registration verification failed: wrong owner');
    }
    
    if (isStillAvailable) {
      throw new Error('Name registration verification failed: name is still available');
    }
    
    console.log('✓ Name registration verified successfully');
    
  } catch (error) {
    console.error('Error during commitment and registration test:', error);
    throw error;
  }
}

/**
 * Test the renewal flow using ETHRegistrar
 */
async function testRenewal(env) {
  console.log('\n=== TEST 2: Name Renewal ===');

  const name = 'renewalismust';
  const user = env.L2.wallets.admin.address;
  const secret = ethers.id('supersecret'); // Just a random secret
  const subregistry = await env.l2.registry.getAddress();
  const resolver = ethers.ZeroAddress;
  const initialDuration = 86400 * 30; // 30 days
  const renewalDuration = 86400 * 365; // 1 year

  console.log(`Registering name for renewal test: ${name}.eth`);
  console.log(`User: ${user}`);
  console.log(`Initial duration: ${initialDuration / 86400} days`);
  console.log(`Renewal duration: ${renewalDuration / 86400} days`);

  try {
    // Step 1: Register a name first
    console.log('\nStep 1: Registering a name for renewal test...');
    
    // First check if the name is available
    const isAvailable = await env.l2.ethRegistrar.available(name);
    if (!isAvailable) {
      console.log('Name is already registered, proceeding with renewal test');
    } else {
      // Calculate price
      const price = await env.l2.ethRegistrar.rentPrice(name, initialDuration);
      const totalPrice = price.base + price.premium;
      
      // Make and submit commitment
      const commitment = await env.l2.ethRegistrar.makeCommitment(
        name,
        user,
        secret,
        subregistry,
        resolver,
        initialDuration
      );
      
      await env.L2.confirm(
        env.l2.ethRegistrar.commit(commitment)
      );
      
      // Wait for minimum commitment age
      const minCommitmentAge = await env.l2.ethRegistrar.minCommitmentAge();
      const waitTime = Number(minCommitmentAge) * 1000 + 1000;
      await setTimeout(waitTime);
      
      // Register
      await env.L2.confirm(
        env.l2.ethRegistrar.register(
          name,
          user,
          secret,
          subregistry,
          resolver,
          initialDuration,
          { value: totalPrice + ethers.parseEther('0.01') }
        )
      );
      
      console.log('Name registered successfully for renewal test');
    }
    
    // Get name data for verification
    const nameData = await env.l2.registry.getNameData(name);
    const tokenId = nameData[0];
    const initialExpiry = nameData[1]; // Element 1 is the expiry
    
    console.log(`TokenID: ${tokenId}`);
    console.log(`Initial expiry: ${new Date(Number(initialExpiry) * 1000).toISOString()}`);
    
    // Step 2: Renew the name
    console.log('\nStep 2: Renewing the name...');
    
    // Calculate renewal price
    const renewalPrice = await env.l2.ethRegistrar.rentPrice(name, renewalDuration);
    const totalRenewalPrice = renewalPrice.base + renewalPrice.premium;
    
    console.log(`Renewal price: ${ethers.formatEther(totalRenewalPrice)} ETH`);
    
    // Renew the name
    const renewTx = await env.L2.confirm(
      env.l2.ethRegistrar.renew(
        name,
        renewalDuration,
        { value: totalRenewalPrice + ethers.parseEther('0.01') }
      )
    );
    
    console.log(`Renewal transaction hash: ${renewTx.hash}`);
    
    // Step 3: Verify renewal
    console.log('\nStep 3: Verifying renewal...');
    
    // Get updated name data
    const updatedNameData = await env.l2.registry.getNameData(name);
    const newExpiry = updatedNameData[1];
    
    console.log(`New expiry: ${new Date(Number(newExpiry) * 1000).toISOString()}`);
    console.log(`Expected minimum expiry: ${new Date((Number(initialExpiry) + renewalDuration) * 1000).toISOString()}`);
    
    if (Number(newExpiry) < Number(initialExpiry) + renewalDuration) {
      throw new Error('Renewal verification failed: expiry not extended correctly');
    }
    
    console.log('✓ Name renewal verified successfully');
    
  } catch (error) {
    console.error('Error during renewal test:', error);
    throw error;
  }
}

// Run the tests if executed directly
if (import.meta.url === `file://${process.argv[1]}`) {
  testRegistration()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error('Test error:', error);
      process.exit(1);
    });
}

export { testCommitmentRegistration, testRenewal };
