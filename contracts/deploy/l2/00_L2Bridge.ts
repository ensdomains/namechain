import { artifacts, execute } from "@rocketh";
import { DEFAULT_L2_CHAIN_ID } from "../../script/setup.js";

export default execute(
  async ({ deploy, get, network, namedAccounts: { deployer } }) => {
    // Get MockSurgeNativeBridge deployment
    const mockSurgeNativeBridge = get<(typeof artifacts.MockSurgeNativeBridge)["abi"]>("MockSurgeNativeBridge");
    
    // Get chain IDs from network or use defaults
    const l2ChainId = network.chain?.id ? BigInt(network.chain.id) : BigInt(DEFAULT_L2_CHAIN_ID);
    const l1ChainId = l2ChainId - 1n;

    // Get the BridgeController deployment (L2BridgeController)
    const bridgeController = get<(typeof artifacts.L2BridgeController)["abi"]>("BridgeController");

    await deploy("L2SurgeBridge", {
      account: deployer,
      artifact: artifacts.L2SurgeBridge,
      args: [
        mockSurgeNativeBridge.address, // Surge native bridge address
        l2ChainId, // L2 Chain ID
        l1ChainId, // L1 Chain ID
        bridgeController.address, // L2BridgeController address
      ],
    });
  },
  {
    tags: ["L2SurgeBridge", "bridge", "l2"],
    dependencies: ["MockSurgeNativeBridge", "L2BridgeController"],
  },
);
