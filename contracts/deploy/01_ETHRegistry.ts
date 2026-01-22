import { artifacts, execute } from "@rocketh";
import { zeroAddress } from "viem";
import { MAX_EXPIRY, ROLES } from "../script/deploy-constants.js";

// TODO: ownership
export default execute(
  async ({ deploy, execute: write, get, namedAccounts: { deployer } }) => {
    const rootRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("RootRegistry");

    const registryDatastore =
      get<(typeof artifacts.RegistryDatastore)["abi"]>("RegistryDatastore");

    const hcaFactory =
      get<(typeof artifacts.MockHCAFactoryBasic)["abi"]>("HCAFactory");

    const registryMetadata = get<
      (typeof artifacts.SimpleRegistryMetadata)["abi"]
    >("SimpleRegistryMetadata");

    const ethRegistry = await deploy("ETHRegistry", {
      account: deployer,
      artifact: artifacts.PermissionedRegistry,
      args: [
        registryDatastore.address,
        hcaFactory.address,
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
        zeroAddress,
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
      "HCAFactory",
      "RegistryMetadata",
    ],
  },
);
