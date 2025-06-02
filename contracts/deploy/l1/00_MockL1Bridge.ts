/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts, get }) => {
    const { deployer } = namedAccounts;

    const bridgeHelper =
      get<(typeof artifacts.MockBridgeHelper)["abi"]>("MockBridgeHelper");

    await deploy("MockL1Bridge", {
      account: deployer,
      artifact: artifacts.MockL1Bridge,
      args: [bridgeHelper.address],
    });
  },
  // finally you can pass tags and dependencies
  {
    tags: ["MockL1Bridge", "mocks", "l1"],
    dependencies: ["MockBridgeHelper"],
  },
);
