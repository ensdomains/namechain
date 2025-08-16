/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";
import { ROLES } from "../constants.ts";
import {
  rateFromAnnualPrice,
  formatRateAsAnnualPrice,
  PRICE_DECIMALS,
} from "../../test/utils/price.ts";

export default execute(
  async ({ deploy, namedAccounts, get, execute: write }) => {
    const { deployer, owner } = namedAccounts;

    const ethRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ETHRegistry");

    const mockUSDC = get("MockUSDC");
    const mockDAI = get("MockDAI");

    // Use owner as beneficiary, or deployer if owner is not set
    const beneficiary = owner || deployer;

    const baseRatePerCp = [
      0n,
      0n,
      rateFromAnnualPrice("640"),
      rateFromAnnualPrice("160"),
      rateFromAnnualPrice("5"),
    ] as const;

    console.table(
      baseRatePerCp.flatMap((rate, i) =>
        rate
          ? { cp: 1 + i, rate, yearly: formatRateAsAnnualPrice(rate, 2) }
          : [],
      ),
    );

    const ethRegistrar = await deploy("ETHRegistrar", {
      account: deployer,
      artifact: artifacts.ETHRegistrar,
      args: [
        {
          ethRegistry: ethRegistry.address,
          beneficiary,
          minCommitmentAge: 60n, // 1 minute,
          maxCommitmentAge: 86400n, // 1 day,
          minRegistrationDuration: 28n * 86400n,
          gracePeriod: 90n * 86400n,
          baseRatePerCp,
          premiumDays: 21n,
          premiumStartingPrice: 100_000_000n * 10n ** BigInt(PRICE_DECIMALS),
          paymentTokens: [mockUSDC.address, mockDAI.address],
        },
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
    dependencies: ["ETHRegistry", "MockTokens"],
  },
);
