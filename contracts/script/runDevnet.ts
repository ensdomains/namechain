import { setupCrossChainEnvironment, CrossChainRelayer } from './setup.js';

setupCrossChainEnvironment()
  .then((env) => {
    // Create a relayer
    const relayer = new CrossChainRelayer(
      env.l1.bridge,
      env.l2.bridge,
      env.l1.wallet,
      env.l2.wallet
    );

    console.log('Setup complete! Cross-chain relayer is running.');
    console.log('Keep this process running to relay cross-chain messages.');

    // Export environment for interactive use
    global.env = env;
    global.relayer = relayer;
    console.log(
      'Environment and relayer exported to global variables for interactive use'
    );
    console.log("L1: http://localhost:8545 Chain ID: 31337");
    console.log("L2: http://localhost:8546 Chain ID: 31338");
  })
  .catch((error) => {
    console.error('Error setting up environment:', error);
    process.exit(1);
  });
