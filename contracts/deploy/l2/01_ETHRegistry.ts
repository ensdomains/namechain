/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";
import { ROLES } from "../constants.js";

export default execute(
  async ({ deploy, namedAccounts, get }) => {
    const { deployer } = namedAccounts;

    const registryDatastore =
      get<(typeof artifacts.RegistryDatastore)["abi"]>("RegistryDatastore");
    const registryMetadata = get<
      (typeof artifacts.SimpleRegistryMetadata)["abi"]
    >("SimpleRegistryMetadata");

    await deploy("ETHRegistry", {
      account: deployer,
      artifact: artifacts.PermissionedRegistry,
      args: [registryDatastore.address, registryMetadata.address, ROLES.ALL],
    });
  },
  // finally you can pass tags and dependencies
  {
    tags: ["ETHRegistry", "l2"],
    dependencies: ["RegistryDatastore", "RegistryMetadata"],
  },
);
