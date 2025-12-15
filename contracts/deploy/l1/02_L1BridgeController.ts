import { artifacts, execute } from "@rocketh";
import { ROLES } from "../constants.js";

export default execute(
  async ({ deploy, execute: write, get, namedAccounts: { deployer } }) => {
    const l1EthRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ETHRegistry");

    // Deploy bridge controller with dummy bridge address first to break circular dependency
    const l1BridgeController = await deploy("BridgeController", {
      account: deployer,
      artifact: artifacts.L1BridgeController,
      args: [l1EthRegistry.address, "0x0000000000000000000000000000000000000000"], // Dummy bridge address
    });

    // Grant registrar and renew roles to the bridge controller on the eth registry
    await write(l1EthRegistry, {
      functionName: "grantRootRoles",
      args: [
        ROLES.OWNER.EAC.REGISTRAR |
          ROLES.OWNER.EAC.RENEW |
          ROLES.OWNER.EAC.BURN,
        l1BridgeController.address,
      ],
      account: deployer,
    });
  },
  {
    tags: ["L1BridgeController", "registry", "l1"],
    dependencies: ["ETHRegistry"], // Remove L1Bridge dependency
  },
);
