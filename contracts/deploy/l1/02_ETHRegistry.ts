import { artifacts, execute } from "@rocketh";
import { MAX_EXPIRY, ROLES } from "../constants.js";

 // TODO: ownership
export default execute(
  async ({ deploy, execute: write, get, namedAccounts: { deployer } }) => {
    const rootRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("RootRegistry");

    const registryDatastore =
      get<(typeof artifacts.RegistryDatastore)["abi"]>("RegistryDatastore");

    const registryCrier =
      get<(typeof artifacts.RegistryCrier)["abi"]>("RegistryCrier");

    const registryMetadata = get<
      (typeof artifacts.SimpleRegistryMetadata)["abi"]
    >("SimpleRegistryMetadata");

    const ethTLDResolver =
      get<(typeof artifacts.ETHTLDResolver)["abi"]>("ETHTLDResolver");

    const ethRegistry = await deploy("ETHRegistry", {
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

    await write(rootRegistry, {
      account: deployer,
      functionName: "register",
      args: [
        "eth",
        deployer, 
        ethRegistry.address,
        ethTLDResolver.address,
        0n,
        MAX_EXPIRY,
      ],
    });
  },
  {
    tags: ["ETHRegistry", "l1"],
    dependencies: [
      "RootRegistry",
      "RegistryDatastore",
      "RegistryCrier",
      "RegistryMetadata",
      "ETHTLDResolver",
    ],
  },
);
