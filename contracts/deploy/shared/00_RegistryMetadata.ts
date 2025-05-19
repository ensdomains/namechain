/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts }) => {
    const { deployer } = namedAccounts;

    await deploy("SimpleRegistryMetadata", {
      account: deployer,
      artifact: artifacts.SimpleRegistryMetadata,
      args: [],
    });
  },
  // finally you can pass tags and dependencies
  { tags: ["RegistryMetadata", "shared"] },
);
