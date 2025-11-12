import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, get, namedAccounts: { deployer } }) => {
    const registryDatastore =
      get<(typeof artifacts.RegistryDatastore)["abi"]>("RegistryDatastore");

    const registryCrier =
      get<(typeof artifacts.RegistryCrier)["abi"]>("RegistryCrier");

    const registryMetadata = get<
      (typeof artifacts.SimpleRegistryMetadata)["abi"]
    >("SimpleRegistryMetadata");

    await deploy("UserRegistryImpl", {
      account: deployer,
      artifact: artifacts.UserRegistry,
      args: [
        registryDatastore.address,
        registryCrier.address,
        registryMetadata.address,
      ],
    });
  },
  {
    tags: ["UserRegistry", "shared"],
    dependencies: ["RegistryDatastore", "RegistryCrier", "RegistryMetadata"],
  },
);
