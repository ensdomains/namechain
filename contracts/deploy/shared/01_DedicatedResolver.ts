import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, get, namedAccounts: { deployer } }) => {
    const hcaFactory =
      get<(typeof artifacts.MockHCAFactoryBasic)["abi"]>("HCAFactory");

    await deploy("DedicatedResolver", {
      account: deployer,
      artifact: artifacts.DedicatedResolver,
      args: [hcaFactory.address],
    });
  },
  {
    tags: ["DedicatedResolver", "shared"],
    dependencies: ["HCAFactory"],
  },
);
