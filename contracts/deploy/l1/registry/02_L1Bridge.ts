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

    await deploy("L1Bridge", {
      account: deployer,
      artifact: artifacts.MockL1Bridge,
      args: [ejectionController.address, mockBridgeHelper.address],
    });
  },
  // finally you can pass tags and dependencies
  {
    tags: ["L1Bridge", "bridge", "l1"],
    dependencies: ["EjectionController", "MockBridgeHelper"],
  }
);
