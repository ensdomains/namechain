import { artifacts, execute } from "@rocketh";
import {
  rateFromAnnualPrice,
  formatAnnualPriceFromRate,
  PRICE_DECIMALS,
} from "../../test/utils/price.ts";

export default execute(
  async ({ deploy, execute: write, get, namedAccounts: { deployer } }) => {
    const tokenPriceOracle = get<
      (typeof artifacts.StableTokenPriceOracle)["abi"]
    >("StableTokenPriceOracle");

    const MockERC20 = artifacts["src/mocks/MockERC20.sol/MockERC20"];
    const mockUSDC = get<(typeof MockERC20)["abi"]>("MockUSDC");
    const mockDAI = get<(typeof MockERC20)["abi"]>("MockDAI");

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
    await deploy("StandardRentPriceOracle", {
      account: deployer,
      artifact: artifacts.StandardRentPriceOracle,
      args: [
        PRICE_DECIMALS,
        baseRatePerCp,
        21n * SEC_PER_DAY, // premiumPeriod
        SEC_PER_DAY, // premiumHalvingPeriod
        100_000_000n * 10n ** BigInt(PRICE_DECIMALS), // premiumPriceInitial
        tokenPriceOracle.address,
        [mockUSDC.address, mockDAI.address],
      ],
    });
  },
  {
    tags: ["StandardRentPriceOracle", "l2"],
    dependencies: ["MockTokens", "StableTokenPriceOracle"],
  },
);
