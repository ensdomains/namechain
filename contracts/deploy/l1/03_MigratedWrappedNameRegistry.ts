import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, get, getV1, namedAccounts: { deployer } }) => {
    const nameWrapperV1 =
      getV1<(typeof artifacts.NameWrapper)["abi"]>("NameWrapper");

    const ethRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ETHRegistry");

    const registryDatastore =
      get<(typeof artifacts.RegistryDatastore)["abi"]>("RegistryDatastore");

    const hcaFactory =
      get<(typeof artifacts.MockHCAFactoryBasic)["abi"]>("HCAFactory");

    const registryMetadata = get<
      (typeof artifacts.SimpleRegistryMetadata)["abi"]
    >("SimpleRegistryMetadata");

    const verifiableFactory =
      get<(typeof artifacts.VerifiableFactory)["abi"]>("VerifiableFactory");

    await deploy("MigratedWrappedNameRegistryImpl", {
      account: deployer,
      artifact: artifacts.MigratedWrappedNameRegistry,
      args: [
        nameWrapperV1.address,
        ethRegistry.address,
        verifiableFactory.address,
        registryDatastore.address,
        hcaFactory.address,
        registryMetadata.address,
      ],
    });
  },
  {
    tags: ["MigratedWrappedNameRegistry", "l1"],
    dependencies: [
      "NameWrapper",
      "HCAFactory",
      "ETHRegistry",
      "VerifiableFactory",
    ],
  },
);
