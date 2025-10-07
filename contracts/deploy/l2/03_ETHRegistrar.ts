import { artifacts, execute } from "@rocketh";
import { ROLES } from "../constants.js";

export default execute(
  async ({
    deploy,
    execute: write,
    get,
    namedAccounts: { deployer, owner },
  }) => {
    const ethRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ETHRegistry");

    const rentPriceOracle = get<(typeof artifacts.IRentPriceOracle)["abi"]>(
      "StandardRentPriceOracle",
    );

    // Use owner as beneficiary, or deployer if owner is not set
    const beneficiary = owner || deployer;

    const SEC_PER_DAY = 86400n;
    const ethRegistrar = await deploy("ETHRegistrar", {
      account: deployer,
      artifact: artifacts.ETHRegistrar,
      args: [
        ethRegistry.address,
        beneficiary,
        60n, // minCommitmentAge
        SEC_PER_DAY, // maxCommitmentAge
        28n * SEC_PER_DAY, // minRegistrationDuration
        rentPriceOracle.address,
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
  {
    tags: ["ETHRegistrar", "l2"],
    dependencies: ["ETHRegistry", "StandardRentPriceOracle"],
  },
);
