import { artifacts, execute } from "@rocketh";
import { DEFAULT_L1_CHAIN_ID, DEFAULT_L2_CHAIN_ID } from "../../script/setup.js";

export default execute(
  async ({ deploy, get, network, namedAccounts: { deployer } }) => {
    // Get MockSurgeBridge deployment
    const mockSurgeBridge = get<(typeof artifacts.MockSurgeBridge)["abi"]>("MockSurgeBridge");
    
    // Get chain IDs from network or use defaults
    const l1ChainId = network.chain?.id ? BigInt(network.chain.id) : BigInt(DEFAULT_L1_CHAIN_ID);
    const l2ChainId = l1ChainId + 1n;

    // Get the BridgeController deployment (L1BridgeController)
    const bridgeController = get<(typeof artifacts.L1BridgeController)["abi"]>("BridgeController");

    await deploy("L1Bridge", {
      account: deployer,
      artifact: artifacts.L1Bridge,
      args: [
        mockSurgeBridge.address, // Surge bridge address
        l1ChainId, // L1 Chain ID
        l2ChainId, // L2 Chain ID
        bridgeController.address, // L1BridgeController address
      ],
    });
  },
  {
    tags: ["L1Bridge", "bridge", "l1"],
    dependencies: ["MockSurgeBridge", "L1BridgeController"],
  },
);
