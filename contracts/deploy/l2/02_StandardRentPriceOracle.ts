import { artifacts, execute } from "@rocketh";
import {
  rateFromAnnualPrice,
  formatAnnualPriceFromRate,
  PRICE_DECIMALS,
} from "../../test/utils/price.js";

export default execute(
  async ({ deploy, read, get, namedAccounts: { deployer } }) => {
    const ethRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ETHRegistry");

    type MockERC20 =
      (typeof artifacts)["src/mocks/MockERC20.sol/MockERC20"]["abi"];
    const mockUSDC = get<MockERC20>("MockUSDC");
    const mockDAI = get<MockERC20>("MockDAI");
    const paymentTokens = [mockUSDC, mockDAI];

    const baseRatePerCp = [
      0n,
      0n,
      rateFromAnnualPrice("640"),
      rateFromAnnualPrice("160"),
      rateFromAnnualPrice("5"),
    ] as const;

    const paymentFactors = await Promise.all(
      paymentTokens.map(async (x) => {
        const [symbol, decimals] = await Promise.all([
          read(x, { functionName: "symbol" }),
          read(x, { functionName: "decimals" }),
        ]);
        return {
          symbol,
          decimals,
          token: x.address,
          numer: 10n ** BigInt(Math.max(decimals - PRICE_DECIMALS, 0)),
          denom: 10n ** BigInt(Math.max(PRICE_DECIMALS - decimals, 0)),
        };
      }),
    );

    console.table(paymentFactors);

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
        ethRegistry.address,
        baseRatePerCp,
        SEC_PER_DAY * 21n, // premiumPeriod
        SEC_PER_DAY, // premiumHalvingPeriod
        100_000_000n * 10n ** BigInt(PRICE_DECIMALS), // premiumPriceInitial
        paymentFactors,
      ],
    });
  },
  {
    tags: ["StandardRentPriceOracle", "l2"],
    dependencies: ["MockTokens", "ETHRegistry"],
  },
);
