import { artifacts, execute } from "@rocketh";
import { ROLES } from "../constants.ts";
import {
  rateFromAnnualPrice,
  formatAnnualPriceFromRate,
  PRICE_DECIMALS,
} from "../../test/utils/price.ts";

export default execute(
  async ({ deploy, namedAccounts, get, execute: write }) => {
    const { deployer, owner } = namedAccounts;

    const ethRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ETHRegistry");

    const tokenPriceOracle = get("StableTokenPriceOracle");

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
          ? { cp: 1 + i, rate, yearly: formatAnnualPriceFromRate(rate, 2) }
          : [],
      ),
    );

    const SEC_PER_DAY = 86400n;
    const ethRegistrar = await deploy("ETHRegistrar", {
      account: deployer,
      artifact: artifacts.ETHRegistrar,
      args: [
        {
          ethRegistry: ethRegistry.address,
          beneficiary,
          minCommitmentAge: 60n, // 1 minute,
          maxCommitmentAge: SEC_PER_DAY,
          minRegistrationDuration: 28n * SEC_PER_DAY,
          priceDecimals: PRICE_DECIMALS,
          tokenPriceOracle: tokenPriceOracle.address,
          baseRatePerCp,
          premiumPeriod: 21n * SEC_PER_DAY,
          premiumHalvingPeriod: SEC_PER_DAY,
          premiumPriceInitial: 100_000_000n * 10n ** BigInt(PRICE_DECIMALS),
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
  {
    tags: ["ETHRegistrar", "registry", "l2"],
    dependencies: ["ETHRegistry", "MockTokens", "StableTokenPriceOracle"],
  },
);
