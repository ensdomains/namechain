import { artifacts, execute } from "@rocketh";
import { MAX_EXPIRY, ROLES } from "../constants.ts";

export default execute(
  async ({ deploy, execute, get, namedAccounts: { deployer } }) => {
    const rootRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("RootRegistry");
    const registryDatastore = get("RegistryDatastore");
    const registryMetadata = get("SimpleRegistryMetadata");
    const ethTLDResolver = get("ETHTLDResolver");

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
