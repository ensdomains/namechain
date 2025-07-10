/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, namedAccounts, get }) => {
    const { deployer } = namedAccounts;

    const rootRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("RootRegistry");

    await deploy("UniversalResolver", {
      account: deployer,
      artifact: artifacts.UniversalResolver2,
      args: [rootRegistry.address, ["x-batch-gateway:true"]],
    });
  },
  // finally you can pass tags and dependencies
  {
    tags: ["UniversalResolver", "l1"],
    dependencies: ["RootRegistry"],
  },
);
