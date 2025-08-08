/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts }) => {
	const { deployer } = namedAccounts;

	await deploy("BatchGatewayProvider", {
	  account: deployer,
	  artifact: artifacts.GatewayProvider,
	  args: [deployer, ['x-batch-gateway:true']],
	});
  },
  // finally you can pass tags and dependencies
  {
	tags: ["GatewayProvider", "l1"],
  },
);
