import { artifacts, execute } from "@rocketh";
import { ROLES } from "../constants.ts";

export default execute(
  async ({ deploy, execute: write, get, namedAccounts: { deployer} }) => {

    const l1EthRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ETHRegistry");

    // TODO: real bridge
    const l1Bridge =
      get<(typeof artifacts.MockL1Bridge)["abi"]>("MockL1Bridge");

    const l1BridgeController = await deploy("L1BridgeController", {
      account: deployer,
      artifact: artifacts.L1BridgeController,
      args: [l1EthRegistry.address, l1Bridge.address],
    });

    // Set the bridge controller on the bridge
    await write(l1Bridge, {
      functionName: "setBridgeController",
      args: [l1BridgeController.address],
      account: deployer,
    });

    // Grant registrar and renew roles to the bridge controller on the eth registry
    await write(l1EthRegistry, {
      functionName: "grantRootRoles",
      args: [
        ROLES.OWNER.EAC.REGISTRAR | ROLES.OWNER.EAC.RENEW | ROLES.OWNER.EAC.BURN,
        l1BridgeController.address,
      ],
      account: deployer,
    });

    // Grant bridge roles to the bridge on the bridge controller
    await write(l1BridgeController, {
      functionName: "grantRootRoles",
      args: [
        ROLES.OWNER.BRIDGE.EJECTOR,
        l1Bridge.address,
      ],
      account: deployer,
    });
  },
  {
    tags: ["L1BridgeController", "registry", "l1"],
    dependencies: ["L1ETHRegistry", "MockL1Bridge"],
  },
);
