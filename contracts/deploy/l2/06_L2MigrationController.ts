/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ get, deploy, namedAccounts, execute: write }) => {
    const { deployer } = namedAccounts;

    const ethRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ETHRegistry");
    const l2Bridge =
      get<(typeof artifacts.MockL2Bridge)["abi"]>("MockL2Bridge");
    const l2EjectionController =
      get<(typeof artifacts.L2EjectionController)["abi"]>("L2EjectionController");
    const registryDatastore =
      get<(typeof artifacts.RegistryDatastore)["abi"]>("RegistryDatastore");
    const registryFactory =
      get<(typeof artifacts.RegistryFactory)["abi"]>("RegistryFactory");

    const l2MigrationController = await deploy("L2MigrationController", {
      account: deployer,
      artifact: artifacts.L2MigrationController,
      args: [
        l2Bridge.address,
        l2EjectionController.address,
        ethRegistry.address,
        registryDatastore.address,
        registryFactory.address,
      ],
    });

    // Set the migration controller on the bridge
    await write(l2Bridge, {
      functionName: "setMigrationController",
      args: [l2MigrationController.address],
      account: deployer,
    });

    // Grant the migration controller role to the L2MigrationController on the L2EjectionController
    await write(l2EjectionController, {
      functionName: "grantRootRoles",
      args: [1n << 0n, l2MigrationController.address], // ROLE_MIGRATION_CONTROLLER
      account: deployer,
    });

    // Grant registrar role to the migration controller on the eth registry
    await write(ethRegistry, {
      functionName: "grantRootRoles",
      args: [1n << 0n, l2MigrationController.address], // ROLE_REGISTRAR
      account: deployer,
    });
  },
  // finally you can pass tags and dependencies
  {
    tags: ["L2MigrationController", "registry", "l2"],
    dependencies: ["ETHRegistry", "MockL2Bridge", "L2EjectionController", "RegistryDatastore", "RegistryFactory"],
  },
); 