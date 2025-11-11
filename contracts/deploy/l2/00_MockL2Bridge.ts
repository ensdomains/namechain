import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts: { deployer } }) => {
    await deploy("MockBridge", {
      account: deployer,
      artifact: artifacts.MockL2Bridge,
      args: [
        "0x0000000000000000000000000000000000000000", // Mock ISurgeBridge address
        BigInt(2), // L2 Chain ID
        BigInt(1), // L1 Chain ID  
        "0x0000000000000000000000000000000000000000", // L2BridgeController address (will be set later)
      ],
    });
  },
  {
    tags: ["MockL2Bridge", "mocks", "l2"],
  },
);
