import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts: { deployer } }) => {
    await deploy("MockBridge", {
      account: deployer,
      artifact: artifacts.MockL1Bridge,
      args: [
        "0x0000000000000000000000000000000000000000", // Mock ISurgeBridge address
        BigInt(1), // L1 Chain ID
        BigInt(2), // L2 Chain ID  
        "0x0000000000000000000000000000000000000000", // L1BridgeController address (will be set later)
      ],
    });
  },
  {
    tags: ["MockL1Bridge", "mocks", "l1"],
  },
);
