import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, get, read, namedAccounts: { deployer } }) => {
    const nameWrapperV1 =
      get<(typeof artifacts.NameWrapper)["abi"]>("NameWrapper");

    const ethRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ETHRegistry");

    const registryDatastore =
      get<(typeof artifacts.RegistryDatastore)["abi"]>("RegistryDatastore");

    const registryMetadata = get<
      (typeof artifacts.SimpleRegistryMetadata)["abi"]
    >("SimpleRegistryMetadata");

    const factory = await deploy("MigratedWrappedNameRegistryFactory", {
      account: deployer,
      artifact: artifacts.VerifiableFactory,
    });

    await deploy("MigratedWrappedNameRegistryImpl", {
      account: deployer,
      artifact: artifacts.MigratedWrappedNameRegistry,
      args: [
        nameWrapperV1.address,
        await read(nameWrapperV1, { functionName: "ens" }), // TODO remove
        factory.address,
        ethRegistry.address,
        registryDatastore.address,
        registryMetadata.address,
      ],
    });
  },
  {
    tags: ["MigratedWrappedNameRegistry", "l1"],
    dependencies: ["NameWrapper", "ETHRegistry"],
  },
);
