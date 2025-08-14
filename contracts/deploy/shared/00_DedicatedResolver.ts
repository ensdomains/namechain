import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts: { deployer } }) => {
    await deploy("DedicatedResolverFactory", {
      account: deployer,
      artifact: artifacts.VerifiableFactory,
    });
    await deploy("DedicatedResolverImpl", {
      account: deployer,
      artifact: artifacts.DedicatedResolver,
    });
  },
  {
    tags: ["DedicatedResolver", "shared"],
  },
);
