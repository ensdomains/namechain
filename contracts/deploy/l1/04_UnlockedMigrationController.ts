import { artifacts, execute } from "@rocketh";
import { ROLES } from "../constants.js";

export default execute(
  async ({
    deploy,
    read,
    execute: write,
    get,
    namedAccounts: { deployer },
  }) => {
    const nameWrapperV1 =
      get<(typeof artifacts.NameWrapper)["abi"]>("NameWrapper");

    const bridgeController =
      get<(typeof artifacts.L1BridgeController)["abi"]>("BridgeController");

    const unlockedMigrationController = await deploy(
      "UnlockedMigrationController",
      {
        account: deployer,
        artifact: artifacts.L1UnlockedMigrationController,
        args: [
          await read(nameWrapperV1, { functionName: "registrar" }), // TODO: remove
          nameWrapperV1.address,
          await read(bridgeController, { functionName: "BRIDGE" }), // TODO: remove
          bridgeController.address,
        ],
      },
    );

    await write(bridgeController, {
      functionName: "grantRootRoles",
      args: [ROLES.OWNER.BRIDGE.EJECTOR, unlockedMigrationController.address],
      account: deployer,
    });
  },
  {
    tags: ["UnlockedMigrationController", "l1"],
    dependencies: ["BridgeController", "NameWrapper"],
  },
);
