/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts, get }) => {
    const { deployer } = namedAccounts;

    const registryDatastore =
      get<(typeof artifacts.RegistryDatastore)["abi"]>("RegistryDatastore");
    const ejectionController =
      get<(typeof artifacts.MockEjectionController)["abi"]>(
        "EjectionController"
      );

    await deploy("L1ETHRegistry", {
      account: deployer,
      artifact: artifacts.L1ETHRegistry,
      args: [registryDatastore.address, ejectionController.address],
    });
  },
  // finally you can pass tags and dependencies
  {
    tags: ["L1ETHRegistry", "registry", "l1"],
    dependencies: ["RegistryDatastore", "EjectionController"],
  }
);
