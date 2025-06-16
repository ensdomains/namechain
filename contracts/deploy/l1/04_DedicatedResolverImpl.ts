import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts }) => {
    const { deployer } = namedAccounts;

    await deploy("DedicatedResolverImpl", {
      account: deployer,
      artifact: artifacts.DedicatedResolver,
    });
  },
  {
    tags: ["DedicatedResolverImpl", "l1"],
    dependencies: [],
  },
);
