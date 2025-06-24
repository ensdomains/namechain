/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts, get }) => {
    const { deployer } = namedAccounts;

    await deploy("MockDurinL1ResolverImpl", {
      account: deployer,
      artifact: artifacts.MockDurinL1Resolver,
      args: [],
    });
  },
  // finally you can pass tags and dependencies
  {
    tags: ["MockDurinL1ResolverImpl", "mocks", "l1"],
    dependencies: [],
  },
);
