import { artifacts, execute } from "@rocketh";
import { ROLES } from "../constants.js";

export default execute(
  async ({ deploy, execute: write, get, namedAccounts: { deployer} }) => {

    const ethRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ETHRegistry");

    // TODO: real bridge
    const l1Bridge =
      get<(typeof artifacts.MockL1Bridge)["abi"]>("MockL1Bridge");

    const l1EjectionController = await deploy("L1EjectionController", {
      account: deployer,
      artifact: artifacts.L1EjectionController,
      args: [ethRegistry.address, l1Bridge.address],
    });

    // Set the ejection controller on the bridge
    await write(l1Bridge, {
      functionName: "setEjectionController",
      args: [l1EjectionController.address],
      account: deployer,
    });

    // Grant registrar and renew roles to the ejection controller on the eth registry
    await write(ethRegistry, {
      functionName: "grantRootRoles",
      args: [
        ROLES.OWNER.EAC.REGISTRAR | ROLES.OWNER.EAC.RENEW | ROLES.OWNER.EAC.BURN,
        l1EjectionController.address,
      ],
      account: deployer,
    });

    // Grant bridge roles to the bridge on the ejection controller
    await write(l1EjectionController, {
      functionName: "grantRootRoles",
      args: [
        ROLES.OWNER.BRIDGE.EJECTOR,
        l1Bridge.address,
      ],
      account: deployer,
    });
  },
  {
    tags: ["L1EjectionController", "registry", "l1"],
    dependencies: ["ETHRegistry", "MockL1Bridge"],
  },
);
