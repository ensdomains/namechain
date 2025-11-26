import { artifacts, execute } from "@rocketh";
import { dnsEncodeName } from "../../test/utils/utils.js";

export default execute(
  async ({ deploy, get, namedAccounts: { deployer } }) => {
    const ethRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ETHRegistry");

    await deploy("RegistryFinder", {
      account: deployer,
      artifact: artifacts.RegistryFinder,
      args: [ethRegistry.address, dnsEncodeName("eth")],
    });
  },
  {
    tags: ["RegistryFinder", "l2"],
    dependencies: ["ETHRegistry"],
  },
);
