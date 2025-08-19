import { artifacts, execute } from "@rocketh";
import { MAX_EXPIRY, ROLES } from "../constants.ts";

export default execute(
  async ({ deploy, execute, get, namedAccounts: { deployer } }) => {
    const rootRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("RootRegistry");

    const registryDatastore =
      get<(typeof artifacts.RegistryDatastore)["abi"]>("RegistryDatastore");

    const registryMetadata = get<
      (typeof artifacts.SimpleRegistryMetadata)["abi"]
    >("SimpleRegistryMetadata");

    const ethTLDResolver =
      get<(typeof artifacts.ETHTLDResolver)["abi"]>("ETHTLDResolver");

    const ethRegistry = await deploy("L1ETHRegistry", {
      account: deployer,
      artifact: artifacts.PermissionedRegistry,
      args: [
        registryDatastore.address,
        registryMetadata.address,
        deployer,
        ROLES.ALL,
      ],
    });

    await execute(rootRegistry, {
      functionName: "register",
      args: [
        "eth",
        deployer,
        ethRegistry.address,
        ethTLDResolver.address,
        0n, // TODO: figure out required roles?
        MAX_EXPIRY,
      ],
      account: deployer,
    });
  },
  {
    tags: ["L1ETHRegistry", "l1"],
    dependencies: [
      "RootRegistry",
      "RegistryDatastore",
      "RegistryMetadata",
      "ETHTLDResolver",
    ],
  },
);
