/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts }) => {
    const { deployer } = namedAccounts;

    await deploy("MockL2Bridge", {
      account: deployer,
      artifact: artifacts.MockL2Bridge,
      args: [],
    });
  },
  // finally you can pass tags and dependencies
  {
    tags: ["MockL2Bridge", "mocks", "l2"],
  },
);
