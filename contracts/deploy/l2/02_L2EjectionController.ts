/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";
import { ROLES } from "../constants.js";

export default execute(
  async ({ get, deploy, namedAccounts, execute: write }) => {
    const { deployer } = namedAccounts;

    const ethRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ETHRegistry");

    // TODO: real bridge
    const l2Bridge =
      get<(typeof artifacts.MockL2Bridge)["abi"]>("MockL2Bridge");

    const l2BridgeController = await deploy("L2EjectionController", {
      account: deployer,
      artifact: artifacts.L2EjectionController,
      args: [ethRegistry.address, l2Bridge.address],
    });

    await write(l2Bridge, {
      functionName: "setEjectionController",
      args: [l2BridgeController.address],
      account: deployer,
    });
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
    tags: ["L2EjectionController", "registry", "l2"],
    dependencies: ["ETHRegistry", "MockL2Bridge"],
  },
);
