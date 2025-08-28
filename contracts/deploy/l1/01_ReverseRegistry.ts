import { artifacts, execute } from "@rocketh";
import { MAX_EXPIRY, ROLES } from "../constants.ts";

// TODO: ownership
export default execute(
  async ({ deploy, execute: write, get, namedAccounts: { deployer } }) => {
    const defaultReverseResolverV1 = get<
      (typeof artifacts.DefaultReverseResolver)["abi"]
    >("DefaultReverseResolver");

    const rootRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("RootRegistry");

    const registryDatastore =
      get<(typeof artifacts.RegistryDatastore)["abi"]>("RegistryDatastore");

    const registryMetadata = get<
      (typeof artifacts.SimpleRegistryMetadata)["abi"]
    >("SimpleRegistryMetadata");

    // create "reverse" registry
    const reverseRegistry = await deploy("ReverseRegistry", {
      account: deployer,
      artifact: artifacts.PermissionedRegistry,
      args: [
        registryDatastore.address,
        registryMetadata.address,
        deployer,
        ROLES.ALL,
      ],
    });

    // register "reverse" with default resolver
    await write(rootRegistry, {
      account: deployer,
      functionName: "register",
      args: [
        "reverse",
        deployer,
        reverseRegistry.address,
        defaultReverseResolverV1.address,
        0n,
        MAX_EXPIRY,
      ],
    });
  },
  {
    tags: ["ReverseRegistry", "l1"],
    dependencies: [
      "DefaultReverseResolver",
      "RootRegistry",
      "RegistryDatastore",
      "SimpleRegistryMetadata",
    ],
  },
);
