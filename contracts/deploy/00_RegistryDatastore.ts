import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts: { deployer } }) => {
    await deploy("RegistryDatastore", {
      account: deployer,
      artifact: artifacts.RegistryDatastore,
      args: [],
    });
  },
  { tags: ["RegistryDatastore", "l1"] },
);
