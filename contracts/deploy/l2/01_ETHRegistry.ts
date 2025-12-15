import { artifacts, execute } from "@rocketh";
import { ROLES } from "../constants.js";

export default execute(
  async ({ deploy, get, namedAccounts: { deployer } }) => {
    const registryDatastore =
      get<(typeof artifacts.RegistryDatastore)["abi"]>("RegistryDatastore");

    const hcaFactory =
      get<(typeof artifacts.MockHCAFactoryBasic)["abi"]>("HCAFactory");

    const registryMetadata = get<
      (typeof artifacts.SimpleRegistryMetadata)["abi"]
    >("SimpleRegistryMetadata");

    await deploy("ETHRegistry", {
      account: deployer,
      artifact: artifacts.PermissionedRegistry,
      args: [
        registryDatastore.address,
        hcaFactory.address,
        registryMetadata.address,
        deployer,
        ROLES.ALL,
      ],
    });
  },
  {
    tags: ["ETHRegistry", "l2"],
    dependencies: ["RegistryDatastore", "HCAFactory", "RegistryMetadata"],
  },
);
