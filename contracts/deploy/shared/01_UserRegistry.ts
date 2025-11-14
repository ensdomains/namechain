import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, get, namedAccounts: { deployer } }) => {
    const registryDatastore =
      get<(typeof artifacts.RegistryDatastore)["abi"]>("RegistryDatastore");

    const registryMetadata = get<
      (typeof artifacts.SimpleRegistryMetadata)["abi"]
    >("SimpleRegistryMetadata");

    await deploy("UserRegistry", {
      account: deployer,
      artifact: artifacts.UserRegistry,
      args: [registryDatastore.address, registryMetadata.address],
    });
  },
  {
    tags: ["UserRegistry", "shared"],
    dependencies: ["RegistryDatastore", "RegistryMetadata"],
  },
);
