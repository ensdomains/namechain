import { artifacts, execute } from "@rocketh";
import { ROLES } from "../constants.js";

export default execute(
  async ({ deploy, execute: write, get, getV1, namedAccounts: { deployer } }) => {
    const nameWrapperV1 =
      getV1<(typeof artifacts.NameWrapper)["abi"]>("NameWrapper");

    const bridgeController =
      get<(typeof artifacts.L1BridgeController)["abi"]>("BridgeController");

    const verifiableFactory =
      get<(typeof artifacts.VerifiableFactory)["abi"]>("VerifiableFactory");

    const migratedWrappedNameRegistryImpl = get<
      (typeof artifacts.MigratedWrappedNameRegistry)["abi"]
    >("MigratedWrappedNameRegistryImpl");

    const lockedMigrationController = await deploy(
      "LockedMigrationController",
      {
        account: deployer,
        artifact: artifacts.L1LockedMigrationController,
        args: [
          nameWrapperV1.address,
          bridgeController.address,
          verifiableFactory.address,
          migratedWrappedNameRegistryImpl.address,
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
      "VerifiableFactory",
      "MigratedWrappedNameRegistryImpl",
    ],
  },
);
