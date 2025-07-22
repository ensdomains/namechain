// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "../src/L2/TokenPriceOracle.sol";
import "../src/mocks/MockPriceOracle.sol";

contract TokenPriceOracleTest is Test {
    MockPriceOracle baseOracle;
    TokenPriceOracle tokenOracle;

    address mockUSDC = address(0x1);
    address mockDAI = address(0x2);

    uint256 constant BASE_PRICE_USD = 10 * 1e18; // $10 in 18 decimals
    uint256 constant PREMIUM_PRICE_USD = 5 * 1e18; // $5 in 18 decimals

    function setUp() public {
        baseOracle = new MockPriceOracle(BASE_PRICE_USD, PREMIUM_PRICE_USD);
    }

    function test_constructor_should_initialize_with_tokens() public {
        address[] memory tokens = new address[](2);
        tokens[0] = mockUSDC;
        tokens[1] = mockDAI;

        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 6; // USDC has 6 decimals
        decimals[1] = 18; // DAI has 18 decimals

        tokenOracle = new TokenPriceOracle(tokens, decimals, 10 * 1e6, 5 * 1e6);

        // Verify the oracle was created and configured correctly
        assertTrue(tokenOracle.isTokenSupported(mockUSDC));
        assertTrue(tokenOracle.isTokenSupported(mockDAI));

        // Verify token configurations
        TokenPriceOracle.TokenConfig memory usdcConfig = tokenOracle.getTokenConfig(mockUSDC);
        assertEq(usdcConfig.decimals, 6);
        assertTrue(usdcConfig.enabled);

        TokenPriceOracle.TokenConfig memory daiConfig = tokenOracle.getTokenConfig(mockDAI);
        assertEq(daiConfig.decimals, 18);
        assertTrue(daiConfig.enabled);

        // Verify default prices are set
        assertEq(tokenOracle.basePrice(), 10 * 1e6);
        assertEq(tokenOracle.premiumPrice(), 5 * 1e6);
    }

    function test_priceInToken_should_handle_different_decimals() public {
        // RED: This will fail because priceInToken doesn't exist yet
        // Setup the token oracle
        address[] memory tokens = new address[](2);
        tokens[0] = mockUSDC;
        tokens[1] = mockDAI;

        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 6; // USDC has 6 decimals
        decimals[1] = 18; // DAI has 18 decimals

        tokenOracle = new TokenPriceOracle(tokens, decimals, 10 * 1e6, 5 * 1e6);

        // Total USD price = $10 (base) + $5 (premium) = $15
        // For USDC (6 decimals): $15 should be 15 * 10^6 = 15,000,000
        // For DAI (18 decimals): $15 should be 15 * 10^18 = 15,000,000,000,000,000,000

        uint256 usdcAmount = tokenOracle.priceInToken("test", 0, 365 days, mockUSDC);
        uint256 daiAmount = tokenOracle.priceInToken("test", 0, 365 days, mockDAI);

        assertEq(usdcAmount, 15 * 10 ** 6); // 15 USDC
        assertEq(daiAmount, 15 * 10 ** 18); // 15 DAI
    }

    function test_price_should_return_usd_amounts_without_base_oracle() public {
        // RED: This will fail because constructor signature will change
        address[] memory tokens = new address[](2);
        tokens[0] = mockUSDC;
        tokens[1] = mockDAI;

        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 6; // USDC
        decimals[1] = 18; // DAI

        // Constructor should only need tokens and decimals, no base oracle
        tokenOracle = new TokenPriceOracle(tokens, decimals, 10 * 1e6, 5 * 1e6);

        // price() should return USD amounts directly
        IPriceOracle.Price memory priceResult = tokenOracle.price("test", 0, 365 days);

        // Should return reasonable USD amounts (e.g., $10 base, $5 premium)
        // Using 6 decimals as default (USDC standard)
        assertEq(priceResult.base, 10 * 1e6); // $10 in 6 decimals
        assertEq(priceResult.premium, 5 * 1e6); // $5 in 6 decimals
    }

    function test_constructor_should_accept_usd_prices() public {
        // RED: This will fail because constructor doesn't accept price parameters
        address[] memory tokens = new address[](2);
        tokens[0] = mockUSDC;
        tokens[1] = mockDAI;

        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 6; // USDC
        decimals[1] = 18; // DAI

        uint256 customBasePrice = 15 * 1e6; // $15 in 6 decimals
        uint256 customPremiumPrice = 3 * 1e6; // $3 in 6 decimals

        tokenOracle = new TokenPriceOracle(tokens, decimals, customBasePrice, customPremiumPrice);

        // Verify custom prices are set
        assertEq(tokenOracle.basePrice(), customBasePrice);
        assertEq(tokenOracle.premiumPrice(), customPremiumPrice);

        // Verify price() returns the custom prices
        IPriceOracle.Price memory priceResult = tokenOracle.price("test", 0, 365 days);
        assertEq(priceResult.base, customBasePrice);
        assertEq(priceResult.premium, customPremiumPrice);
    }

    function test_constructor_should_revert_with_zero_base_price() public {
        // RED: Test zero base price validation
        address[] memory tokens = new address[](1);
        tokens[0] = mockUSDC;

        uint8[] memory decimals = new uint8[](1);
        decimals[0] = 6;

        vm.expectRevert(abi.encodeWithSelector(TokenPriceOracle.InvalidPrice.selector, 0));
        new TokenPriceOracle(tokens, decimals, 0, 5 * 1e6);
    }

    function test_constructor_should_revert_with_zero_premium_price() public {
        // RED: Test zero premium price validation
        address[] memory tokens = new address[](1);
        tokens[0] = mockUSDC;

        uint8[] memory decimals = new uint8[](1);
        decimals[0] = 6;

        vm.expectRevert(abi.encodeWithSelector(TokenPriceOracle.InvalidPrice.selector, 0));
        new TokenPriceOracle(tokens, decimals, 10 * 1e6, 0);
    }

    function test_constructor_should_revert_with_array_length_mismatch() public {
        // RED: Test array length mismatch validation
        address[] memory tokens = new address[](2);
        tokens[0] = mockUSDC;
        tokens[1] = mockDAI;

        uint8[] memory decimals = new uint8[](1); // Wrong length
        decimals[0] = 6;

        vm.expectRevert(abi.encodeWithSelector(TokenPriceOracle.ArrayLengthMismatch.selector));
        new TokenPriceOracle(tokens, decimals, 10 * 1e6, 5 * 1e6);
    }

    function test_priceInToken_should_revert_for_unsupported_token() public {
        // RED: Test unsupported token
        address[] memory tokens = new address[](1);
        tokens[0] = mockUSDC;

        uint8[] memory decimals = new uint8[](1);
        decimals[0] = 6;

        tokenOracle = new TokenPriceOracle(tokens, decimals, 10 * 1e6, 5 * 1e6);

        address unsupportedToken = address(0x999);
        vm.expectRevert(abi.encodeWithSelector(TokenPriceOracle.TokenNotSupported.selector, unsupportedToken));
        tokenOracle.priceInToken("test", 0, 365 days, unsupportedToken);
    }

    function test_priceInToken_should_handle_extreme_decimals() public {
        // RED: Test edge cases with extreme decimal values
        address[] memory tokens = new address[](3);
        tokens[0] = address(0x1); // 0 decimals
        tokens[1] = address(0x2); // 1 decimal
        tokens[2] = address(0x3); // 18 decimals (max)

        uint8[] memory decimals = new uint8[](3);
        decimals[0] = 0; // Extreme low
        decimals[1] = 1; // Very low
        decimals[2] = 18; // Standard high

        tokenOracle = new TokenPriceOracle(tokens, decimals, 10 * 1e6, 5 * 1e6);

        // Test 0 decimals: $15 should be 15
        uint256 amount0 = tokenOracle.priceInToken("test", 0, 365 days, tokens[0]);
        assertEq(amount0, 15);

        // Test 1 decimal: $15 should be 150
        uint256 amount1 = tokenOracle.priceInToken("test", 0, 365 days, tokens[1]);
        assertEq(amount1, 150);

        // Test 18 decimals: $15 should be 15 * 1e18
        uint256 amount18 = tokenOracle.priceInToken("test", 0, 365 days, tokens[2]);
        assertEq(amount18, 15 * 1e18);
    }

    function test_constructor_should_handle_empty_token_arrays() public {
        // RED: Test empty arrays
        address[] memory tokens = new address[](0);
        uint8[] memory decimals = new uint8[](0);

        // Should succeed with empty arrays
        tokenOracle = new TokenPriceOracle(tokens, decimals, 10 * 1e6, 5 * 1e6);

        // Verify no tokens are supported
        assertFalse(tokenOracle.isTokenSupported(mockUSDC));
        assertFalse(tokenOracle.isTokenSupported(mockDAI));
    }

    function test_getTokenConfig_should_return_default_for_unsupported_token() public {
        // RED: Test querying config for unsupported token
        address[] memory tokens = new address[](1);
        tokens[0] = mockUSDC;

        uint8[] memory decimals = new uint8[](1);
        decimals[0] = 6;

        tokenOracle = new TokenPriceOracle(tokens, decimals, 10 * 1e6, 5 * 1e6);

        // Query unsupported token should return default values
        TokenPriceOracle.TokenConfig memory config = tokenOracle.getTokenConfig(mockDAI);
        assertEq(config.decimals, 0);
        assertFalse(config.enabled);
    }

    function test_priceInToken_should_handle_large_prices() public {
        // RED: Test very large USD prices to check for overflow
        address[] memory tokens = new address[](2);
        tokens[0] = mockUSDC;
        tokens[1] = mockDAI;

        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 6;
        decimals[1] = 18;

        uint256 largeBasePrice = 100000000 * 1e6; // $100M in 6 decimals
        uint256 largePremiumPrice = 50000000 * 1e6; // $50M in 6 decimals

        tokenOracle = new TokenPriceOracle(tokens, decimals, largeBasePrice, largePremiumPrice);

        // Total: $150M should not overflow
        uint256 usdcAmount = tokenOracle.priceInToken("test", 0, 365 days, mockUSDC);
        assertEq(usdcAmount, 150000000 * 1e6); // $150M USDC

        uint256 daiAmount = tokenOracle.priceInToken("test", 0, 365 days, mockDAI);
        assertEq(daiAmount, 150000000 * 1e18); // $150M DAI
    }

    function test_priceInToken_should_handle_very_small_prices() public {
        // RED: Test very small prices for precision
        address[] memory tokens = new address[](2);
        tokens[0] = mockUSDC;
        tokens[1] = mockDAI;

        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 6;
        decimals[1] = 18;

        uint256 smallBasePrice = 1; // $0.000001 in 6 decimals
        uint256 smallPremiumPrice = 1; // $0.000001 in 6 decimals

        tokenOracle = new TokenPriceOracle(tokens, decimals, smallBasePrice, smallPremiumPrice);

        // Total: $0.000002
        uint256 usdcAmount = tokenOracle.priceInToken("test", 0, 365 days, mockUSDC);
        assertEq(usdcAmount, 2); // 2 micro-USDC

        uint256 daiAmount = tokenOracle.priceInToken("test", 0, 365 days, mockDAI);
        assertEq(daiAmount, 2 * 1e12); // 2 * 1e12 wei DAI (0.000002 DAI)
    }

    function test_constructor_should_handle_duplicate_tokens() public {
        // RED: Test duplicate token addresses - should still work but only store once
        address[] memory tokens = new address[](3);
        tokens[0] = mockUSDC;
        tokens[1] = mockDAI;
        tokens[2] = mockUSDC; // Duplicate

        uint8[] memory decimals = new uint8[](3);
        decimals[0] = 6;
        decimals[1] = 18;
        decimals[2] = 8; // Different decimals for same token

        tokenOracle = new TokenPriceOracle(tokens, decimals, 10 * 1e6, 5 * 1e6);

        // Should still support both tokens
        assertTrue(tokenOracle.isTokenSupported(mockUSDC));
        assertTrue(tokenOracle.isTokenSupported(mockDAI));

        // Last configuration should win for duplicate token
        TokenPriceOracle.TokenConfig memory usdcConfig = tokenOracle.getTokenConfig(mockUSDC);
        assertEq(usdcConfig.decimals, 8); // Should be 8, not 6
        assertTrue(usdcConfig.enabled);
    }
}
