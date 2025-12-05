import { artifacts, execute } from "@rocketh";
import { labelhash } from "viem";
import { MAX_EXPIRY, ROLES } from "../constants.ts";

// TODO: ownership
export default execute(
  async ({
    deploy,
    execute: write,
    read,
    get,
    getV1,
    namedAccounts: { deployer },
  }) => {
    const defaultReverseResolverV1 = getV1<
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

    const entry = await read(rootRegistry, {
      functionName: 'getEntry',
      args: [BigInt(labelhash('reverse'))],
    });

    if (entry.expiry !== 0n) {

        // set subregistry
      await write(rootRegistry, {
        account: deployer,
        functionName: "setSubregistry",
        args: [BigInt(labelhash('reverse')), reverseRegistry.address],
      });

      // set resolver
      await write(rootRegistry, {
        account: deployer,
        functionName: "setResolver",
        args: [BigInt(labelhash('reverse')), defaultReverseResolverV1.address],
      });
    } else {
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

    }
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
