/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";
import { ROLES } from "../constants.ts";

export default execute(
  async ({ deploy, execute: write, get, namedAccounts }) => {
    const { deployer } = namedAccounts;

    const ethRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ETHRegistry");

    const registryDatastore =
      get<(typeof artifacts.RegistryDatastore)["abi"]>("RegistryDatastore");

    // Deploy bridge controller with dummy bridge address first to break circular dependency
    const l2BridgeController = await deploy("BridgeController", {
      account: deployer,
      artifact: artifacts.L2BridgeController,
      args: ["0x0000000000000000000000000000000000000000", ethRegistry.address, registryDatastore.address], // Dummy bridge address
    });

    // Grant registrar and renew roles to the bridge controller on the eth registry
    await write(ethRegistry, {
      functionName: "grantRootRoles",
      args: [
        ROLES.OWNER.EAC.REGISTRAR | ROLES.OWNER.EAC.RENEW,
        l2BridgeController.address,
      ],
      account: deployer,
    });
  },
  // finally you can pass tags and dependencies
  {
    tags: ["L2BridgeController", "registry", "l2"],
    dependencies: [
      "ETHRegistry",
      "RegistryDatastore",
      "VerifiableFactory",
    ], // Remove L2Bridge dependency
  },
);
