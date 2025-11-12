import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts: { deployer } }) => {
    await deploy("RegistryCrier", {
      account: deployer,
      artifact: artifacts.RegistryCrier,
      args: [],
    });
  },
  {
    tags: ["RegistryCrier", "shared"],
    dependencies: [],
  },
);
