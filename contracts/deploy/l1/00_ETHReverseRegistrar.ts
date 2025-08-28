import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts: { deployer } }) => {
    // create a new registrar for "addr.reverse"
    await deploy("ETHReverseRegistrar", {
      account: deployer,
      artifact: artifacts.StandaloneReverseRegistrar,
    });
  },
  {
    tags: ["ETHReverseRegistrar", "l1"],
  },
);
