import { artifacts, execute } from "@rocketh";
import { ROLES } from "../constants.js";

export default execute(
  async ({ deploy, execute: write, get, namedAccounts: { deployer } }) => {
    const nameWrapperV1 =
      get<(typeof artifacts.NameWrapper)["abi"]>("NameWrapper");

    const bridgeController =
      get<(typeof artifacts.L1BridgeController)["abi"]>("BridgeController");

    const MigratedWrapperRegistryFactory = get<
      (typeof artifacts.VerifiableFactory)["abi"]
    >("MigratedWrapperRegistryFactory");

    const MigratedWrapperRegistryImpl = get<
      (typeof artifacts.MigratedWrapperRegistry)["abi"]
    >("MigratedWrapperRegistryImpl");

    const lockedMigrationController = await deploy(
      "LockedMigrationController",
      {
        account: deployer,
        artifact: artifacts.LockedMigrationController,
        args: [
          nameWrapperV1.address,
          bridgeController.address,
          MigratedWrapperRegistryFactory.address,
          MigratedWrapperRegistryImpl.address,
        ],
      },
    );

    await write(bridgeController, {
      functionName: "grantRootRoles",
      args: [ROLES.OWNER.BRIDGE.EJECTOR, lockedMigrationController.address],
      account: deployer,
    });
  },
  {
    tags: ["LockedMigrationController", "l1"],
    dependencies: [
      "NameWrapper",
      "BridgeController",
      "MigratedWrapperRegistryImpl",
      "MigratedWrapperRegistryFactory",
    ],
  },
);
