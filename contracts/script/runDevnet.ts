import { setupCrossChainEnvironment, CrossChainRelayer } from './setup.js';

setupCrossChainEnvironment()
  .then((env) => {
    // Create a relayer
    const relayer = new CrossChainRelayer(
      env.l1.bridge,
      env.l2.bridge,
      env.L1,
      env.L2
    );

    console.log('Setup complete! Cross-chain relayer is running.');
    console.log('Keep this process running to relay cross-chain messages.');

    // Export environment for interactive use
    global.env = env;
    global.relayer = relayer;
    console.log(
      'Environment and relayer exported to global variables for interactive use'
    );
    console.log(`L1: ${env.L1.endpoint} Chain ID: ${env.L1.chain}`);
    console.log(`L2: ${env.L2.endpoint} Chain ID: ${env.L2.chain}`);
  })
  .catch((error) => {
    console.error('Error setting up environment:', error);
    process.exit(1);
  });
