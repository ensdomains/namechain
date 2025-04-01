/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts, get }) => {
    const { deployer } = namedAccounts;

    const registryDatastore =
      get<(typeof artifacts.RegistryDatastore)["abi"]>("RegistryDatastore");

    await deploy("RootRegistry", {
      account: deployer,
      artifact: artifacts.RootRegistry,
      args: [registryDatastore.address],
    });
  },
  // finally you can pass tags and dependencies
  {
    tags: ["RootRegistry", "registry", "l1"],
    dependencies: ["RegistryDatastore"],
  }
);
