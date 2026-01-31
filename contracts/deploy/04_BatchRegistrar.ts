import { artifacts, execute } from "@rocketh";
import { ROLES } from "../script/deploy-constants.js";

export default execute(
  async ({ deploy, execute: write, get, namedAccounts: { deployer } }) => {
    const ethRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ETHRegistry");

    const batchRegistrar = await deploy("BatchRegistrar", {
      account: deployer,
      artifact: artifacts.BatchRegistrar,
      args: [ethRegistry.address],
    });

    await write(ethRegistry, {
      account: deployer,
      functionName: "grantRootRoles",
      args: [
        ROLES.OWNER.EAC.REGISTRAR | ROLES.OWNER.EAC.RENEW,
        batchRegistrar.address,
      ],
    });
  },
  {
    tags: ["BatchRegistrar", "l1"],
    dependencies: ["ETHRegistry"],
  },
);
