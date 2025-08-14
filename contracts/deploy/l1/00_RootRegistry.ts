import { artifacts, execute } from "@rocketh";
import { ROLES } from "../constants.js";

export default execute(
  async ({ deploy, get, namedAccounts: { deployer } }) => {
    const registryDatastore = get("RegistryDatastore");
    const registryMetadata = get("SimpleRegistryMetadata");

    await deploy("RootRegistry", {
      account: deployer,
      artifact: artifacts.PermissionedRegistry,
      args: [
        registryDatastore.address,
        registryMetadata.address,
        deployer,
        ROLES.ALL,
      ],
    });
  },
  {
    tags: ["RootRegistry", "l1"],
    dependencies: ["RegistryDatastore", "RegistryMetadata"],
  },
);
