import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts: { deployer } }) => {
    await deploy("MockSurgeBridge", {
      account: deployer,
      artifact: artifacts.MockSurgeBridge,
      args: [],
    });
  },
  {
    tags: ["MockSurgeBridge", "mocks", "shared"],
  },
);