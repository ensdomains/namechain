import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts: { deployer } }) => {
    await deploy("BatchGatewayProvider", {
      account: deployer,
      artifact: artifacts.GatewayProvider,
      args: [deployer, ["x-batch-gateway:true"]],
    });
  },
  {
    tags: ["BatchGatewayProvider", "l1"],
  },
);
