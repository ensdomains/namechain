/// we import what we need from the @rocketh alias, see ../rocketh.ts
import { artifacts, execute } from "@rocketh";
import {
  dollarsPerYearToNdpsExact,
  ndpsToDollarsPerYearStringExact,
} from "../../test/utils/ndps.ts";

// nanodollars per second pricing
const PRICE_5_CHAR = dollarsPerYearToNdpsExact("5");
const PRICE_4_CHAR = dollarsPerYearToNdpsExact("160");
const PRICE_3_CHAR = dollarsPerYearToNdpsExact("640");

export default execute(
  async ({ deploy, namedAccounts, get }) => {
    const { deployer } = namedAccounts;

    // Get the deployed mock token addresses
    const mockUSDC = get("MockUSDC");
    const mockDAI = get("MockDAI");

    const tokenAddresses = [mockUSDC.address, mockDAI.address];
    const tokenDecimals = [6, 18]; // USDC: 6 decimals, DAI: 18 decimals
    const rentPrices = [PRICE_5_CHAR, PRICE_4_CHAR, PRICE_3_CHAR, 0n, 0n]; // Array of rent prices (5 prices for StablePriceOracle)

    // Use the full path to access StablePriceOracle from artifacts
    const StablePriceOracle =
      artifacts["src/L2/StablePriceOracle.sol/StablePriceOracle"];

    await deploy("PriceOracle", {
      account: deployer,
      artifact: StablePriceOracle,
      args: [tokenAddresses, tokenDecimals, rentPrices],
    });

    console.log(`✅ TokenPriceOracle deployed with:`);
    console.log(
      `   - Base Price: $${ndpsToDollarsPerYearStringExact(PRICE_5_CHAR)}`,
    );
    console.log(
      `   - Rent Prices: [${rentPrices.map((p) => `$${ndpsToDollarsPerYearStringExact(p)}`).join(", ")}]`,
    );
    console.log(`   - Supported Tokens:`);
    console.log(`     - MockUSDC (6 decimals): ${tokenAddresses[0]}`);
    console.log(`     - MockDAI (18 decimals): ${tokenAddresses[1]}`);
  },
  // finally you can pass tags and dependencies
  { tags: ["PriceOracle", "registry", "l2"], dependencies: ["MockTokens"] },
);
