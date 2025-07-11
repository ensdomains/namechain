/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts }) => {
    const { deployer } = namedAccounts;

    await deploy("RegistryFactory", {
      account: deployer,
      artifact: artifacts.RegistryFactory,
      args: [],
    });
  },
  // finally you can pass tags and dependencies
  {
    tags: ["RegistryFactory", "registry", "l2"],
    dependencies: [],
  },
); 