/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts, get }) => {
    const { deployer } = namedAccounts;

    const rootRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("RootRegistry");
    const batchGatewayProvider = get<(typeof artifacts.GatewayProvider)["abi"]>(
      "BatchGatewayProvider",
    );

    await deploy("UniversalResolver", {
      account: deployer,
      artifact: artifacts.UniversalResolverV2,
      args: [rootRegistry.address, batchGatewayProvider.address],
    });
  },
  // finally you can pass tags and dependencies
  {
    tags: ["UniversalResolver", "l1"],
    dependencies: ["RootRegistry", "BatchGatewayProvider"],
  },
);
