import { artifacts, execute } from "@rocketh";
import { ROLES } from "../constants.js";

export default execute(
  async ({ deploy, execute: write, get, namedAccounts: { deployer } }) => {
    const nameWrapperV1 =
      get<(typeof artifacts.NameWrapper)["abi"]>("NameWrapper");

    const bridgeController =
      get<(typeof artifacts.L1BridgeController)["abi"]>("BridgeController");

    const MigratedWrappedNameRegistryFactory = get<
      (typeof artifacts.VerifiableFactory)["abi"]
    >("MigratedWrappedNameRegistryFactory");

    const MigratedWrappedNameRegistryImpl = get<
      (typeof artifacts.MigratedWrappedNameRegistry)["abi"]
    >("MigratedWrappedNameRegistryImpl");

    const lockedMigrationController = await deploy(
      "LockedMigrationController",
      {
        account: deployer,
        artifact: artifacts.LockedMigrationController,
        args: [
          nameWrapperV1.address,
          bridgeController.address,
          MigratedWrappedNameRegistryFactory.address,
          MigratedWrappedNameRegistryImpl.address,
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
      "MigratedWrappedNameRegistryImpl",
      "MigratedWrappedNameRegistryFactory",
    ],
  },
);
