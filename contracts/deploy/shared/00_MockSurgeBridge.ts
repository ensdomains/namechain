import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts: { deployer } }) => {
    await deploy("MockSurgeNativeBridge", {
      account: deployer,
      artifact: artifacts.MockSurgeNativeBridge,
      args: [],
    });
  },
  {
    tags: ["MockSurgeNativeBridge", "mocks", "shared"],
  },
);