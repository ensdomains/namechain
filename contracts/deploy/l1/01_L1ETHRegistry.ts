/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";
import { zeroAddress } from "viem";
import { MAX_EXPIRY, ROLES } from "../constants.js";

export default execute(
  async ({ deploy, namedAccounts, get, execute: write }) => {
    const { deployer } = namedAccounts;

    const rootRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("RootRegistry");
    const registryDatastore =
      get<(typeof artifacts.RegistryDatastore)["abi"]>("RegistryDatastore");
    const registryMetadata = get<
      (typeof artifacts.SimpleRegistryMetadata)["abi"]
    >("SimpleRegistryMetadata");

    const l1EthRegistry = await deploy("L1ETHRegistry", {
      account: deployer,
      artifact: artifacts.PermissionedRegistry,
      args: [
        registryDatastore.address,
        registryMetadata.address,
        deployer,
        ROLES.ALL,
      ],
    });

    await write(rootRegistry, {
      functionName: "register",
      args: [
        "eth",
        deployer,
        l1EthRegistry.address,
        // TODO: replace with resolver
        zeroAddress,
        0n, // TODO: figure out required roles?
        MAX_EXPIRY,
      ],
      account: deployer,
    });
  },
  // finally you can pass tags and dependencies
  {
    tags: ["L1ETHRegistry", "l1"],
    dependencies: ["RootRegistry", "RegistryDatastore", "RegistryMetadata"],
  },
);
