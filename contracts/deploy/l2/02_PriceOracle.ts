import { artifacts, execute } from "@rocketh";

// USD prices in 6 decimals (USDC standard)
const BASE_PRICE_USD = 10n * 10n ** 6n; // $10.00

export default execute(
  async ({ deploy, get, namedAccounts: { deployer } }) => {
    // Get the deployed mock token addresses
    const mockUSDC = get("MockUSDC");
    const mockDAI = get("MockDAI");

    const tokenAddresses = [mockUSDC.address, mockDAI.address];
    const tokenDecimals = [6, 18]; // USDC: 6 decimals, DAI: 18 decimals
    const rentPrices = [BASE_PRICE_USD, BASE_PRICE_USD, BASE_PRICE_USD, 0n, 0n]; // Array of rent prices (5 prices for StablePriceOracle)

    // Use the full path to access StablePriceOracle from artifacts
    const StablePriceOracle =
      artifacts["src/L2/StablePriceOracle.sol/StablePriceOracle"];

    await deploy("PriceOracle", {
      account: deployer,
      artifact: StablePriceOracle,
      args: [tokenAddresses, tokenDecimals, rentPrices],
    });

    console.log(`✅ TokenPriceOracle deployed with:`);
    console.log(`   - Base Price: $${Number(BASE_PRICE_USD) / 10 ** 6}`);
    console.log(
      `   - Rent Prices: [${rentPrices.map((p) => `$${Number(p) / 10 ** 6}`).join(", ")}]`,
    );
    console.log(`   - Supported Tokens:`);
    console.log(`     - MockUSDC (6 decimals): ${tokenAddresses[0]}`);
    console.log(`     - MockDAI (18 decimals): ${tokenAddresses[1]}`);
  },
  { tags: ["PriceOracle", "registry", "l2"], dependencies: ["MockTokens"] },
);