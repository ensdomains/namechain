import { artifacts, execute } from "@rocketh";

export default execute(
  async ({ deploy, read, get, namedAccounts: { deployer, owner } }) => {
    const ethRegistry =
      get<(typeof artifacts.PermissionedRegistry)["abi"]>("ETHRegistry");

    type MockERC20 =
      (typeof artifacts)["src/mocks/MockERC20.sol/MockERC20"]["abi"];
    const mockUSDC = get<MockERC20>("MockUSDC");
    const mockDAI = get<MockERC20>("MockDAI");
    const paymentTokens = [mockUSDC, mockDAI];

    // see: StandardPricing.sol
    const SEC_PER_YEAR = 31_557_600n;
    const SEC_PER_DAY = 86400n;
    const PRICE_DECIMALS = 12;
    const PRICE_SCALE = 10n ** BigInt(PRICE_DECIMALS);
    const PREMIUM_PRICE_INITIAL = PRICE_SCALE * 100_000_000n;
    const PREMIUM_HALVING_PERIOD = SEC_PER_DAY;
    const PREMIUM_PERIOD = SEC_PER_DAY * 21n;

    const baseRatePerCp = [
      0n,
      0n,
      PRICE_SCALE * 640n,
      PRICE_SCALE * 160n,
      PRICE_SCALE * 5n,
    ].map((x) => (x + SEC_PER_YEAR - 1n) / SEC_PER_YEAR);

    const paymentFactors = await Promise.all(
      paymentTokens.map(async (x) => {
        const [symbol, decimals] = await Promise.all([
          read(x, { functionName: "symbol" }),
          read(x, { functionName: "decimals" }),
        ]);
        return {
          MockERC20: symbol,
          decimals,
          token: x.address,
          numer: 10n ** BigInt(Math.max(decimals - PRICE_DECIMALS, 0)),
          denom: 10n ** BigInt(Math.max(PRICE_DECIMALS - decimals, 0)),
        };
      }),
    );

    console.table(paymentFactors);

    console.table(
      baseRatePerCp.flatMap((rate, i) => {
        const yearly = (
          Number(rate * SEC_PER_YEAR) / Number(PRICE_SCALE)
        ).toFixed(2);
        return rate ? { cp: 1 + i, rate, yearly } : [];
      }),
    );

    await deploy("StandardRentPriceOracle", {
      account: deployer,
      artifact: artifacts.StandardRentPriceOracle,
      args: [
        owner,
        ethRegistry.address,
        baseRatePerCp,
        PREMIUM_PRICE_INITIAL,
        PREMIUM_HALVING_PERIOD,
        PREMIUM_PERIOD,
        paymentFactors,
      ],
    });
  },
  {
    tags: ["StandardRentPriceOracle", "l2"],
    dependencies: ["MockTokens", "ETHRegistry"],
  },
);
