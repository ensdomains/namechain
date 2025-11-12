import { artifacts, execute } from "@rocketh";
import { DEFAULT_L2_CHAIN_ID } from "../../script/setup.js";

export default execute(
  async ({ deploy, get, network, namedAccounts: { deployer } }) => {
    // Get MockSurgeBridge deployment
    const mockSurgeBridge = get<(typeof artifacts.MockSurgeBridge)["abi"]>("MockSurgeBridge");
    
    // Get chain IDs from network or use defaults
    const l2ChainId = network.chain?.id ? BigInt(network.chain.id) : BigInt(DEFAULT_L2_CHAIN_ID);
    const l1ChainId = l2ChainId - 1n;

    // Get the BridgeController deployment (L2BridgeController)
    const bridgeController = get<(typeof artifacts.L2BridgeController)["abi"]>("BridgeController");

    await deploy("L2Bridge", {
      account: deployer,
      artifact: artifacts.L2Bridge,
      args: [
        mockSurgeBridge.address, // Surge bridge address
        l2ChainId, // L2 Chain ID
        l1ChainId, // L1 Chain ID
        bridgeController.address, // L2BridgeController address
      ],
    });
  },
  {
    tags: ["L2Bridge", "bridge", "l2"],
    dependencies: ["MockSurgeBridge", "L2BridgeController"],
  },
);
