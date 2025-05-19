/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts, get }) => {
    const { deployer } = namedAccounts;

    const bridgeHelper =
      get<(typeof artifacts.MockBridgeHelper)["abi"]>("MockBridgeHelper");

    await deploy("MockL2Bridge", {
      account: deployer,
      artifact: artifacts.MockL2Bridge,
      args: [bridgeHelper.address],
    });
  },
  // finally you can pass tags and dependencies
  {
    tags: ["MockL2Bridge", "mocks", "l2"],
    dependencies: ["MockBridgeHelper"],
  },
);
