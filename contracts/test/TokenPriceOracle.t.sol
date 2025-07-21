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
    
    uint256 constant BASE_PRICE_USD = 10 * 1e18;  // $10 in 18 decimals
    uint256 constant PREMIUM_PRICE_USD = 5 * 1e18; // $5 in 18 decimals
    
    function setUp() public {
        baseOracle = new MockPriceOracle(BASE_PRICE_USD, PREMIUM_PRICE_USD);
    }

    function test_constructor_should_initialize_with_tokens() public {
        address[] memory tokens = new address[](2);
        tokens[0] = mockUSDC;
        tokens[1] = mockDAI;
        
        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 6;  // USDC has 6 decimals
        decimals[1] = 18; // DAI has 18 decimals
        
        tokenOracle = new TokenPriceOracle(tokens, decimals);
        
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
        decimals[0] = 6;  // USDC has 6 decimals
        decimals[1] = 18; // DAI has 18 decimals
        
        tokenOracle = new TokenPriceOracle(tokens, decimals);
        
        // Total USD price = $10 (base) + $5 (premium) = $15
        // For USDC (6 decimals): $15 should be 15 * 10^6 = 15,000,000
        // For DAI (18 decimals): $15 should be 15 * 10^18 = 15,000,000,000,000,000,000
        
        uint256 usdcAmount = tokenOracle.priceInToken("test", 0, 365 days, mockUSDC);
        uint256 daiAmount = tokenOracle.priceInToken("test", 0, 365 days, mockDAI);
        
        assertEq(usdcAmount, 15 * 10**6);  // 15 USDC
        assertEq(daiAmount, 15 * 10**18);  // 15 DAI
    }


    function test_price_should_return_usd_amounts_without_base_oracle() public {
        // RED: This will fail because constructor signature will change
        address[] memory tokens = new address[](2);
        tokens[0] = mockUSDC;
        tokens[1] = mockDAI;
        
        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 6;  // USDC
        decimals[1] = 18; // DAI
        
        // Constructor should only need tokens and decimals, no base oracle
        tokenOracle = new TokenPriceOracle(tokens, decimals);
        
        // price() should return USD amounts directly
        IPriceOracle.Price memory priceResult = tokenOracle.price("test", 0, 365 days);
        
        // Should return reasonable USD amounts (e.g., $10 base, $5 premium)  
        // Using 6 decimals as default (USDC standard)
        assertEq(priceResult.base, 10 * 1e6);     // $10 in 6 decimals
        assertEq(priceResult.premium, 5 * 1e6);   // $5 in 6 decimals
    }
}