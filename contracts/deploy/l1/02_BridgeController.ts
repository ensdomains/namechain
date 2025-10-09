import { artifacts, execute } from "@rocketh";
import { ROLES } from "../constants.js";

export default execute(
  async ({ deploy, execute: write, get, namedAccounts: { deployer } }) => {
    const ethRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ETHRegistry");

    // TODO: real bridge
    const bridge = get<(typeof artifacts.MockL1Bridge)["abi"]>("MockBridge");

    const bridgeController = await deploy("BridgeController", {
      account: deployer,
      artifact: artifacts.L1BridgeController,
      args: [ethRegistry.address, bridge.address],
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
        ROLES.OWNER.REGISTRY.REGISTRAR |
          ROLES.OWNER.REGISTRY.RENEW |
          ROLES.OWNER.REGISTRY.BURN,
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
  {
    tags: ["BridgeController", "l1"],
    dependencies: ["ETHRegistry", "MockBridge"],
  },
);
