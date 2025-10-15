import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts: { deployer } }) => {
    await deploy("MockBridge", {
      account: deployer,
      artifact: artifacts.MockL2Bridge,
      args: [],
    });
  },
  {
    tags: ["MockL2Bridge", "mocks", "l2"],
  },
);
