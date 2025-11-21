import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts: { deployer } }) => {
    await deploy("MockBridge", {
      account: deployer,
      artifact: artifacts.MockL1Bridge,
      args: [],
    });
  },
  {
    tags: ["MockL1Bridge", "mocks", "l1"],
  },
);
