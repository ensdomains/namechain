/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts }) => {
    const { deployer } = namedAccounts;

    await deploy("MockBridgeHelper", {
      account: deployer,
      artifact: artifacts.MockBridgeHelper,
      args: [],
    });
  },
  // finally you can pass tags and dependencies
  { tags: ["MockBridgeHelper", "shared"] }
);
