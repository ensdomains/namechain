import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, get, namedAccounts: { deployer } }) => {
    const nameWrapperV1 =
      get<(typeof artifacts.NameWrapper)["abi"]>("NameWrapper");

    const ethRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ETHRegistry");

    const registryDatastore =
      get<(typeof artifacts.RegistryDatastore)["abi"]>("RegistryDatastore");

    const registryMetadata = get<
      (typeof artifacts.SimpleRegistryMetadata)["abi"]
    >("SimpleRegistryMetadata");

    const factory = await deploy("MigratedWrapperRegistryFactory", {
      account: deployer,
      artifact: artifacts.VerifiableFactory,
    });

    await deploy("MigratedWrapperRegistryImpl", {
      account: deployer,
      artifact: artifacts.MigratedWrapperRegistry,
      args: [
        nameWrapperV1.address,
        factory.address,
        ethRegistry.address,
        registryDatastore.address,
        registryMetadata.address,
      ],
    });
  },
  {
    tags: ["MigratedWrapperRegistry", "l1"],
    dependencies: [
      "ReverseRegistrar", // remove after https://github.com/ensdomains/ens-contracts/pull/490
      "NameWrapper",
      "ETHRegistry",
    ],
  },
);
