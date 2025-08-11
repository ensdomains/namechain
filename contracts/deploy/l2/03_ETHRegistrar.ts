/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";
import { ROLES } from "../constants.js";

const MIN_COMMITMENT_AGE = 60n; // 1 minute
const MAX_COMMITMENT_AGE = 86400n; // 1 day

export default execute(
  async ({ deploy, namedAccounts, get, execute: write }) => {
    const { deployer, owner } = namedAccounts;

    const ethRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ETHRegistry");
    
    // PriceOracle can be either StablePriceOracle or ExponentialPremiumPriceOracle
    // Both inherit from TokenPriceOracle and have compatible interfaces
    const priceOracle =
      get<(typeof artifacts["src/L2/TokenPriceOracle.sol/TokenPriceOracle"])["abi"]>("PriceOracle");

    // Use owner as beneficiary, or deployer if owner is not set
    const beneficiary = owner || deployer;

    const ethRegistrar = await deploy("ETHRegistrar", {
      account: deployer,
      artifact: artifacts.ETHRegistrar,
      args: [
        ethRegistry.address,
        priceOracle.address,
        MIN_COMMITMENT_AGE,
        MAX_COMMITMENT_AGE,
        beneficiary,
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
