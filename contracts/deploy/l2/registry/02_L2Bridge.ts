/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts, get }) => {
    const { deployer } = namedAccounts;

    const ejectionController =
          get<(typeof artifacts.MockEjectionController)["abi"]>(
            "EjectionController"
          );

    const mockBridgeHelper =
          get<(typeof artifacts.MockBridgeHelper)["abi"]>(
            "MockBridgeHelper"
          );

    await deploy("L2Bridge", {
      account: deployer,
      artifact: artifacts.MockL2Bridge,
      args: [ejectionController.address, mockBridgeHelper.address],
    });
  },
  // finally you can pass tags and dependencies
  {
    tags: ["L2Bridge", "bridge", "l2"],
    dependencies: ["EjectionController", "MockBridgeHelper"],
  }
);
