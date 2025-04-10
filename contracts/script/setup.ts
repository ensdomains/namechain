// setup.ts - Cross-chain ENS v2 testing with blocksmith.js
import { Foundry } from "@adraffy/blocksmith";
import { ethers } from "ethers";
import { CrossChainRelayer } from "./CrossChainRelayer.js";

/**
 * Sets up the cross-chain testing environment using blocksmith.js
 * @ref https://github.com/adraffy/blocksmith.js
 * @returns Environment with L1 and L2 contracts and a relayer
 */
export async function setupCrossChainEnvironment() {
  console.log('Setting up cross-chain ENS v2 environment...');
  
  // Launch two separate Anvil instances for L1 and L2
  const [L1, L2] = await Promise.all([
    Foundry.launch({ 
      chain: 31337, 
      port: 8545,
    }),
    Foundry.launch({ 
      chain: 31338, 
      port: 8546,
    })
  ]);
  
  console.log(`L1: Chain ID ${L1.chain}, URL: ${L1.endpoint}`);
  console.log(`L2: Chain ID ${L2.chain}, URL: ${L2.endpoint}`);
  
  // Deploy contracts to both chains
  console.log('Deploying contracts...');
  
  // Deploy registries
  const l1Registry = await L1.deploy({ file: 'MockL1Registry' });
  const l2Registry = await L2.deploy({ file: 'MockL2Registry' });
  
  // Deploy bridge helpers
  const l1BridgeHelper = await L1.deploy({ file: 'MockBridgeHelper' });
  const l2BridgeHelper = await L2.deploy({ file: 'MockBridgeHelper' });
  
  // Deploy bridges (with temporary target addresses)
  const l1Bridge = await L1.deploy({ 
    file: 'MockL1Bridge',
    args: [ethers.ZeroAddress]
  });
  
  const l2Bridge = await L2.deploy({ 
    file: 'MockL2Bridge', 
    args: [ethers.ZeroAddress]
  });
  
  // Deploy controllers with proper connections
  const l1Controller = await L1.deploy({ 
    file: 'MockL1MigrationController', 
    args: [
      await l1Registry.getAddress(),
      await l1BridgeHelper.getAddress(),
      await l1Bridge.getAddress()
    ]
  });
  
  const l2Controller = await L2.deploy({ 
    file: 'MockL2MigrationController', 
    args: [
      await l2Registry.getAddress(),
      await l2BridgeHelper.getAddress(),
      await l2Bridge.getAddress()
    ]
  });
  
  // Set the correct target controllers for the bridges
  await L1.confirm(l1Bridge.setTargetContract(await l1Controller.getAddress()));
  await L2.confirm(l2Bridge.setTargetContract(await l2Controller.getAddress()));
  
  console.log('Cross-chain environment setup complete!');
  
  // Return all deployed contracts, providers, and the relayer
  return {
    L1,
    L2,
    l1: {
      registry: l1Registry,
      bridge: l1Bridge,
      bridgeHelper: l1BridgeHelper,
      controller: l1Controller
    },
    l2: {
      registry: l2Registry,
      bridge: l2Bridge,
      bridgeHelper: l2BridgeHelper,
      controller: l2Controller
    },
    // Safe shutdown function to properly terminate WebSocket connections
    shutdown: async () => {
      console.log('Shutting down environment...');
      
      const safeShutdown = async (instance) => {
        try {
          // First terminate any WebSocket connections cleanly
          if (instance.provider instanceof ethers.WebSocketProvider) {
            // Access internal provider properties if available
            const websocket = instance.provider._websocket;
            if (websocket && typeof websocket.terminate === 'function') {
              websocket.terminate();
            }
          }
          
          // Then call the shutdown method
          await instance.shutdown();
        } catch (error) {
          console.error(`Error shutting down instance: ${error.message}`);
        }
      };
      
      // Sequential shutdown to avoid race conditions
      await safeShutdown(L1);
      await safeShutdown(L2);
      
      console.log('Environment shutdown complete');
    }
  };
}

// Re-export CrossChainRelayer for convenience
export { CrossChainRelayer };
