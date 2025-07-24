/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";

// USD prices in 6 decimals (USDC standard)
const BASE_PRICE_USD = 10 * 10**6;     // $10.00

export default execute(
  async ({ deploy, namedAccounts, get }) => {
    const { deployer } = namedAccounts;

    // Get the deployed mock token addresses
    const mockUSDC = get("MockUSDC");
    const mockDAI = get("MockDAI");

    const tokenAddresses = [mockUSDC.address, mockDAI.address];
    const tokenDecimals = [6, 18]; // USDC: 6 decimals, DAI: 18 decimals
    const rentPrices = [BASE_PRICE_USD]; // Array of rent prices (base price)

    await deploy("PriceOracle", {
      account: deployer,
      artifact: artifacts.TokenPriceOracle,
      args: [
        tokenAddresses,
        tokenDecimals,
        rentPrices,
      ],
    });

    console.log(`✅ TokenPriceOracle deployed with:`)
    console.log(`   - Base Price: $${BASE_PRICE_USD / 10**6}`);
    console.log(`   - Rent Prices: [${rentPrices.map(p => `$${p / 10**6}`).join(', ')}]`);
    console.log(`   - Supported Tokens:`);
    console.log(`     - MockUSDC (6 decimals): ${tokenAddresses[0]}`);
    console.log(`     - MockDAI (18 decimals): ${tokenAddresses[1]}`);
  },
  // finally you can pass tags and dependencies
  { tags: ["PriceOracle", "registry", "l2"], dependencies: ["MockTokens"] },
);
