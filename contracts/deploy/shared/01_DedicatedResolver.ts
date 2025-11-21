import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts: { deployer } }) => {
    await deploy("DedicatedResolver", {
      account: deployer,
      artifact: artifacts.DedicatedResolver,
    });
  },
  {
    tags: ["DedicatedResolver", "shared"],
    dependencies: ["VerifiableFactory"],
  },
);
