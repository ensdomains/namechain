import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, get, namedAccounts: { deployer } }) => {
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
  {
    tags: ["UniversalResolver", "l1"],
    dependencies: ["RootRegistry", "BatchGatewayProvider"],
  },
);
