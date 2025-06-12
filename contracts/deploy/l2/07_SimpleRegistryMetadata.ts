import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts }) => {
    const { deployer } = namedAccounts;

    await deploy("SimpleRegistryMetadata", {
      account: deployer,
      artifact: artifacts.SimpleRegistryMetadata,
    });
  },
  {
    tags: ["SimpleRegistryMetadata", "l2"],
    dependencies: [],
  },
);
