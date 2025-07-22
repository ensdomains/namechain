/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";
import { ROLES } from "../constants.js";

const MIN_COMMITMENT_AGE = 60n; // 1 minute
const MAX_COMMITMENT_AGE = 86400n; // 1 day

export default execute(
  async ({ deploy, namedAccounts, get, execute: write }) => {
    const { deployer } = namedAccounts;

    const ethRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ETHRegistry");
    const priceOracle =
      get<(typeof artifacts.TokenPriceOracle)["abi"]>("PriceOracle");

    const ethRegistrar = await deploy("ETHRegistrar", {
      account: deployer,
      artifact: artifacts.ETHRegistrar,
      args: [
        ethRegistry.address,
        priceOracle.address,
        MIN_COMMITMENT_AGE,
        MAX_COMMITMENT_AGE,
      ],
    });

    await write(ethRegistry, {
      functionName: "grantRootRoles",
      args: [
        ROLES.OWNER.EAC.REGISTRAR | ROLES.OWNER.EAC.RENEW,
        ethRegistrar.address,
      ],
      account: deployer,
    });
  },
  // finally you can pass tags and dependencies
  {
    tags: ["ETHRegistrar", "registry", "l2"],
    dependencies: ["ETHRegistry", "PriceOracle"],
  },
);
