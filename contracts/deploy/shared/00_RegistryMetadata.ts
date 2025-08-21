import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts: { deployer } }) => {
    await deploy("SimpleRegistryMetadata", {
      account: deployer,
      artifact: artifacts.SimpleRegistryMetadata,
      args: [],
    });
  },
  { tags: ["RegistryMetadata", "shared"] },
);
