/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";
import { ROLES } from "../constants.js";

export default execute(
  async ({ get, deploy, namedAccounts, execute: write }) => {
    const { deployer } = namedAccounts;

    const ethRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ETHRegistry");
    const l2Bridge =
      get<(typeof artifacts.MockL2Bridge)["abi"]>("MockL2Bridge");
    const registryDatastore =
      get<(typeof artifacts.RegistryDatastore)["abi"]>("RegistryDatastore");
    const verifiableFactory =
      get<(typeof artifacts.VerifiableFactory)["abi"]>("VerifiableFactory");

    // Deploy UserRegistry implementation
    const userRegistryImplementation = await deploy("UserRegistry", {
      account: deployer,
      artifact: artifacts.UserRegistry,
      args: [],
    });

    const l2BridgeController = await deploy("L2BridgeController", {
      account: deployer,
      artifact: artifacts.L2BridgeController,
      args: [
        l2Bridge.address,
        ethRegistry.address,
        registryDatastore.address,
        verifiableFactory.address,
        userRegistryImplementation.address,
      ],
    });

    // Set the bridge controller on the bridge
    await write(l2Bridge, {
      functionName: "setBridgeController",
      args: [l2BridgeController.address],
      account: deployer,
    });

    // Grant registrar and renew roles to the bridge controller on the eth registry
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
    tags: ["L2BridgeController", "registry", "l2"],
    dependencies: ["ETHRegistry", "MockL2Bridge", "RegistryDatastore", "VerifiableFactory"],
  },
); 