/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";
import { ROLES } from "../constants.ts";

export default execute(
  async ({ deploy, execute: write, get, namedAccounts }) => {
    const { deployer } = namedAccounts;

    const ethRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ETHRegistry");

    const bridge = get<(typeof artifacts.MockL2Bridge)["abi"]>("MockBridge");

    const registryDatastore =
      get<(typeof artifacts.RegistryDatastore)["abi"]>("RegistryDatastore");

    const bridgeController = await deploy("BridgeController", {
      account: deployer,
      artifact: artifacts.L2BridgeController,
      args: [bridge.address, ethRegistry.address, registryDatastore.address],
    });

    // Set the bridge controller on the bridge
    await write(bridge, {
      functionName: "setBridgeController",
      args: [bridgeController.address],
      account: deployer,
    });

    // Grant registrar and renew roles to the bridge controller on the eth registry
    await write(ethRegistry, {
      functionName: "grantRootRoles",
      args: [
        ROLES.OWNER.EAC.REGISTRAR |
          ROLES.OWNER.EAC.RENEW |
          ROLES.OWNER.EAC.SET_RESOLVER |
          ROLES.OWNER.EAC.SET_SUBREGISTRY |
          ROLES.OWNER.EAC.SET_TOKEN_OBSERVER,
        bridgeController.address,
      ],
      account: deployer,
    });

    // Grant bridge roles to the bridge on the bridge controller
    await write(bridgeController, {
      functionName: "grantRootRoles",
      args: [ROLES.OWNER.BRIDGE.EJECTOR, bridge.address],
      account: deployer,
    });
  },
  // finally you can pass tags and dependencies
  {
    tags: ["BridgeController", "registry", "l2"],
    dependencies: [
      "ETHRegistry",
      "MockBridge",
      "RegistryDatastore",
      "VerifiableFactory",
    ],
  },
);
