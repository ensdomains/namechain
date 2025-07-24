/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";
import { ROLES } from "../constants.js";

export default execute(
  async ({ get, deploy, namedAccounts, execute: write }) => {
    const { deployer } = namedAccounts;

    const l1EthRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("L1ETHRegistry");

    // TODO: real bridge
    const l1Bridge =
      get<(typeof artifacts.MockL1Bridge)["abi"]>("MockL1Bridge");

    const l1EjectionController = await deploy("L1EjectionController", {
      account: deployer,
      artifact: artifacts.L1EjectionController,
      args: [l1EthRegistry.address, l1Bridge.address],
    });

    // Set the ejection controller on the bridge
    await write(l1Bridge, {
      functionName: "setEjectionController",
      args: [l1EjectionController.address],
      account: deployer,
    });

    // Grant registrar and renew roles to the ejection controller on the eth registry
    await write(l1EthRegistry, {
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
        ROLES.OWNER.BRIDGE.EJECTOR | ROLES.OWNER.BRIDGE.MIGRATOR,
        l1Bridge.address,
      ],
      account: deployer,
    });
  },
  // finally you can pass tags and dependencies
  {
    tags: ["L1EjectionController", "registry", "l1"],
    dependencies: ["L1ETHRegistry", "MockL1Bridge"],
  },
);
