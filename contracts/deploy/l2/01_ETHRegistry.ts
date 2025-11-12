import { artifacts, execute } from "@rocketh";
import { ROLES } from "../constants.js";

export default execute(
  async ({ deploy, get, namedAccounts: { deployer } }) => {
    const registryDatastore =
      get<(typeof artifacts.RegistryDatastore)["abi"]>("RegistryDatastore");

    const registryCrier =
      get<(typeof artifacts.RegistryCrier)["abi"]>("RegistryCrier");

    const registryMetadata = get<
      (typeof artifacts.SimpleRegistryMetadata)["abi"]
    >("SimpleRegistryMetadata");

    await deploy("ETHRegistry", {
      account: deployer,
      artifact: artifacts.PermissionedRegistry,
      args: [
        registryDatastore.address,
        registryCrier.address,
        registryMetadata.address,
        deployer,
        ROLES.ALL,
      ],
    });
  },
  {
    tags: ["ETHRegistry", "l2"],
    dependencies: ["RegistryDatastore", "RegistryCrier", "RegistryMetadata"],
  },
);
