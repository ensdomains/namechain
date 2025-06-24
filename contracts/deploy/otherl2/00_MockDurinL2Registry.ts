/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts, get }) => {
    const { deployer } = namedAccounts;

    await deploy("MockDurinL2Registry", {
      account: deployer,
      artifact: artifacts.MockDurinL2Registry,
      args: [],
    });
  },
  // finally you can pass tags and dependencies
  {
    tags: ["MockDurinL2Registry", "mocks", "otherl2"],
    dependencies: [""],
  },
);
