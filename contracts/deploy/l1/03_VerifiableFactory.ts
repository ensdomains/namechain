import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts }) => {
    const { deployer } = namedAccounts;

    await deploy("VerifiableFactory", {
      account: deployer,
      artifact: artifacts.VerifiableFactory,
    });
  },
  {
    tags: ["VerifiableFactory", "l1"],
    dependencies: [], // No dependencies needed
  },
);