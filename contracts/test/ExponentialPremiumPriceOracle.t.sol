// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";

import "../src/L2/ExponentialPremiumPriceOracle.sol";
import "../src/L2/ITokenPriceOracle.sol";
import "../src/mocks/MockERC20.sol";
import {IPriceOracle} from "@ens/contracts/ethregistrar/IPriceOracle.sol";

contract TestExponentialPremiumPriceOracle is Test {
    ExponentialPremiumPriceOracle priceOracle;
    MockERC20 usdc;      // 6 decimals
    MockERC20 dai;       // 18 decimals

    // ENS pricing constants (nanodollars per second)
    uint256 constant PRICE_5_CHAR = 158;   // ~$5/year
    uint256 constant PRICE_4_CHAR = 5072;  // ~$160/year
    uint256 constant PRICE_3_CHAR = 20289; // ~$640/year
    
    // Premium constants  
    uint256 constant START_PREMIUM_USD = 100_000_000 * 1e6; // $100 million in 6 decimals
    uint256 constant TOTAL_DAYS = 21; // 21-day decay period

    function setUp() public {
        // Create mock tokens
        usdc = new MockERC20("USDC", "USDC", 6);
        dai = new MockERC20("DAI", "DAI", 18);

        // Setup token configuration
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(dai);
        
        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 6;  // USDC
        decimals[1] = 18; // DAI
        
        // Price array: [5+char, 4char, 3char, 2char, 1char]  
        uint256[] memory rentPrices = new uint256[](5);
        rentPrices[0] = PRICE_5_CHAR; // 5+ chars
        rentPrices[1] = PRICE_4_CHAR; // 4 chars
        rentPrices[2] = PRICE_3_CHAR; // 3 chars  
        rentPrices[3] = 0; // 2 chars (not supported)
        rentPrices[4] = 0; // 1 char (not supported)
        
        priceOracle = new ExponentialPremiumPriceOracle(
            tokens, 
            decimals, 
            rentPrices,
            START_PREMIUM_USD,
            TOTAL_DAYS
        );
    }

    function test_constructor_sets_parameters() public view {
        // This test will initially fail because ExponentialPremiumPriceOracle doesn't exist yet
        // Testing that the contract can be instantiated with correct parameters
        assertTrue(address(priceOracle) != address(0), "Contract should be deployed");
    }

    function test_inherits_from_StablePriceOracle() public view {
        // Test that base pricing works (inherited from StablePriceOracle)
        uint256 duration = 365 days;
        IPriceOracle.Price memory price = priceOracle.price("testname", 0, duration);
        
        // Should have base price from StablePriceOracle
        uint256 expectedBasePrice = PRICE_5_CHAR * duration;
        assertEq(price.base, expectedBasePrice, "Should inherit base pricing from StablePriceOracle");
        
        // Premium should be 0 for non-expired names
        assertEq(price.premium, 0, "Should have no premium for non-expired names");
    }

    function test_premium_for_expired_names() public {
        uint256 duration = 365 days;
        
        // Set up a scenario where name expired 91 days ago (1 day past grace period)
        uint256 nameExpiry = 1000; // Some past timestamp
        uint256 currentTime = nameExpiry + 91 days; // 91 days after expiry
        vm.warp(currentTime);
        
        IPriceOracle.Price memory price = priceOracle.price("expiredname", nameExpiry, duration);
        
        // Should still have base price
        uint256 expectedBasePrice = PRICE_5_CHAR * duration;
        assertEq(price.base, expectedBasePrice, "Should have base price");
        
        // Should have premium for expired name (this will fail until we implement exponential decay)
        assertGt(price.premium, 0, "Should have premium for expired name past grace period");
    }

    function test_grace_period_behavior() public {
        uint256 duration = 365 days;
        uint256 nameExpiry = 1000;
        
        // Test within grace period (89 days after expiry)
        vm.warp(nameExpiry + 89 days);
        IPriceOracle.Price memory priceWithinGrace = priceOracle.price("expiredname", nameExpiry, duration);
        assertEq(priceWithinGrace.premium, 0, "Should have no premium within grace period");
        
        // Test exactly at grace period boundary (90 days after expiry)
        vm.warp(nameExpiry + 90 days);
        IPriceOracle.Price memory priceAtBoundary = priceOracle.price("expiredname", nameExpiry, duration);
        assertEq(priceAtBoundary.premium, 0, "Should have no premium exactly at grace period");
        
        // Test just past grace period (91 days after expiry)
        vm.warp(nameExpiry + 91 days);
        IPriceOracle.Price memory priceAfterGrace = priceOracle.price("expiredname", nameExpiry, duration);
        assertGt(priceAfterGrace.premium, 0, "Should have premium after grace period");
    }

    function test_exponential_decay_over_time() public {
        uint256 duration = 365 days;
        uint256 nameExpiry = 1000;
        
        // Test premium 1 day after grace period
        vm.warp(nameExpiry + 91 days);
        uint256 premium1Day = priceOracle.price("expiredname", nameExpiry, duration).premium;
        
        // Test premium 2 days after grace period  
        vm.warp(nameExpiry + 92 days);
        uint256 premium2Days = priceOracle.price("expiredname", nameExpiry, duration).premium;
        
        // Test premium 7 days after grace period
        vm.warp(nameExpiry + 98 days);
        uint256 premium7Days = priceOracle.price("expiredname", nameExpiry, duration).premium;
        
        // Premium should decrease over time due to exponential decay
        assertGt(premium1Day, premium2Days, "Premium should decrease from day 1 to day 2");
        assertGt(premium2Days, premium7Days, "Premium should decrease from day 2 to day 7");
    }

    function test_decayedPremium_public_function() public view {
        // Test the public decayedPremium function directly
        uint256 startPremium = START_PREMIUM_USD;
        
        // Test 0 elapsed time
        uint256 premium0 = priceOracle.decayedPremium(startPremium, 0);
        assertEq(premium0, startPremium, "Premium should equal start premium at 0 elapsed");
        
        // Test 1 day elapsed
        uint256 premium1Day = priceOracle.decayedPremium(startPremium, 1 days);
        assertEq(premium1Day, startPremium / 2, "Premium should halve after 1 day");
        
        // Test 2 days elapsed
        uint256 premium2Days = priceOracle.decayedPremium(startPremium, 2 days);
        assertEq(premium2Days, startPremium / 4, "Premium should quarter after 2 days");
        
        // Test very long time elapsed (should approach 0)
        uint256 premiumLongTime = priceOracle.decayedPremium(startPremium, 50 days);
        assertLt(premiumLongTime, startPremium / 1000, "Premium should be very small after long time");
    }

    function test_token_conversion_with_premium() public {
        uint256 duration = 365 days;
        uint256 nameExpiry = 1000;
        
        // Set up expired scenario
        vm.warp(nameExpiry + 91 days);
        
        // Get total price (base + premium)
        IPriceOracle.Price memory price = priceOracle.price("expiredname", nameExpiry, duration);
        uint256 totalUsdPrice = price.base + price.premium;
        
        // Test USDC conversion (6 decimals - matches USD_DECIMALS)
        uint256 usdcAmount = priceOracle.priceInToken("expiredname", nameExpiry, duration, address(usdc));
        assertEq(usdcAmount, totalUsdPrice, "USDC amount should match total USD price");
        
        // Test DAI conversion (18 decimals)
        uint256 daiAmount = priceOracle.priceInToken("expiredname", nameExpiry, duration, address(dai));
        assertEq(daiAmount, totalUsdPrice * 1e12, "DAI amount should be scaled up by 10^12");
        
        // Verify premium is included
        assertGt(price.premium, 0, "Should have premium");
        assertGt(usdcAmount, price.base, "Total price should be greater than base price");
    }

    function test_non_expired_names_have_no_premium() public {
        uint256 duration = 365 days;
        uint256 futureExpiry = block.timestamp + 1000; // Future expiry
        
        IPriceOracle.Price memory price = priceOracle.price("futurename", futureExpiry, duration);
        
        // Should have base price but no premium
        assertGt(price.base, 0, "Should have base price");
        assertEq(price.premium, 0, "Should have no premium for future expiry");
    }

    function test_premium_becomes_zero_at_end_value() public {
        uint256 duration = 365 days;
        uint256 nameExpiry = 1000;
        
        // Wait a very long time so premium approaches endValue
        vm.warp(nameExpiry + TOTAL_DAYS * 1 days + 90 days);
        
        IPriceOracle.Price memory price = priceOracle.price("expiredname", nameExpiry, duration);
        
        // Premium should be 0 or very close to 0 when it reaches endValue
        assertLt(price.premium, START_PREMIUM_USD / 1000, "Premium should be very small or zero after total decay period");
    }
}