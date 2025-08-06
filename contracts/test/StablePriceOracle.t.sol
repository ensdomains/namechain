// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";

import "../src/L2/StablePriceOracle.sol";
import "../src/L2/ITokenPriceOracle.sol";
import "../src/mocks/MockERC20.sol";
import {IPriceOracle} from "@ens/contracts/ethregistrar/IPriceOracle.sol";

contract TestStablePriceOracle is Test {
    StablePriceOracle priceOracle;
    MockERC20 usdc;      // 6 decimals
    MockERC20 dai;       // 18 decimals  
    MockERC20 lowDecimalToken;   // 4 decimals
    MockERC20 highDecimalToken;  // 21 decimals

    // ENS pricing constants (nanodollars per second)
    uint256 constant PRICE_5_CHAR = 158;   // ~$5/year
    uint256 constant PRICE_4_CHAR = 5072;  // ~$160/year
    uint256 constant PRICE_3_CHAR = 20289; // ~$640/year

    function setUp() public {
        // Create mock tokens with different decimals
        usdc = new MockERC20("USDC", "USDC", 6);
        dai = new MockERC20("DAI", "DAI", 18);
        lowDecimalToken = new MockERC20("LDT", "LDT", 4);
        highDecimalToken = new MockERC20("HDT", "HDT", 21);

        // Setup StablePriceOracle with length-based pricing
        address[] memory tokens = new address[](4);
        tokens[0] = address(usdc);
        tokens[1] = address(dai);
        tokens[2] = address(lowDecimalToken);
        tokens[3] = address(highDecimalToken);
        
        uint8[] memory decimals = new uint8[](4);
        decimals[0] = 6;  // USDC
        decimals[1] = 18; // DAI
        decimals[2] = 4;  // Low Decimal Token
        decimals[3] = 21; // High Decimal Token
        
        // Price array: [5+char, 4char, 3char, 2char, 1char]  
        uint256[] memory rentPrices = new uint256[](5);
        rentPrices[0] = PRICE_5_CHAR; // 5+ chars
        rentPrices[1] = PRICE_4_CHAR; // 4 chars
        rentPrices[2] = PRICE_3_CHAR; // 3 chars  
        rentPrices[3] = 0; // 2 chars (not supported)
        rentPrices[4] = 0; // 1 char (not supported)
        
        priceOracle = new StablePriceOracle(tokens, decimals, rentPrices);
    }

    // Test length-based pricing logic
    function test_length_based_pricing() public view {
        uint256 duration = 365 days;
        
        // Test 5+ character name
        IPriceOracle.Price memory price5 = priceOracle.price("alice", 0, duration);
        assertEq(price5.base, PRICE_5_CHAR * duration);
        assertEq(price5.premium, 0);
        
        // Test 4 character name
        IPriceOracle.Price memory price4 = priceOracle.price("test", 0, duration);
        assertEq(price4.base, PRICE_4_CHAR * duration);
        assertEq(price4.premium, 0);
        
        // Test 3 character name  
        IPriceOracle.Price memory price3 = priceOracle.price("eth", 0, duration);
        assertEq(price3.base, PRICE_3_CHAR * duration);
        assertEq(price3.premium, 0);
        
        // Test unsupported lengths (should return 0)
        IPriceOracle.Price memory price2 = priceOracle.price("ab", 0, duration);
        assertEq(price2.base, 0);
        assertEq(price2.premium, 0);
        
        IPriceOracle.Price memory price1 = priceOracle.price("a", 0, duration);
        assertEq(price1.base, 0);
        assertEq(price1.premium, 0);
    }

    // Test standard decimal conversion (6 decimals - same as USD_DECIMALS)
    function test_priceInToken_standard_decimals() public view {
        uint256 duration = 365 days;
        string memory name = "testname"; // 8+ chars -> uses PRICE_5_CHAR
        
        uint256 expectedBasePrice = PRICE_5_CHAR * duration;
        
        // USDC (6 decimals) - should match base price exactly
        uint256 usdcAmount = priceOracle.priceInToken(name, 0, duration, address(usdc));
        assertEq(usdcAmount, expectedBasePrice);
    }

    // Test high decimal conversion (18 decimals)
    function test_priceInToken_high_decimals() public view {
        uint256 duration = 365 days;
        string memory name = "testname";
        
        uint256 expectedBasePrice = PRICE_5_CHAR * duration;
        
        // DAI (18 decimals) - should be scaled up by 10^12
        uint256 daiAmount = priceOracle.priceInToken(name, 0, duration, address(dai));
        assertEq(daiAmount, expectedBasePrice * 1e12);
    }

    // Test low decimal conversion with rounding (4 decimals)
    function test_priceInToken_low_decimals_rounding() public view {
        uint256 duration = 365 days;
        string memory name = "testname";
        
        uint256 expectedBasePrice = PRICE_5_CHAR * duration;
        
        // LDT (4 decimals) - should be scaled down by 10^2 with rounding up
        uint256 ldtAmount = priceOracle.priceInToken(name, 0, duration, address(lowDecimalToken));
        uint256 expectedLdtAmount = expectedBasePrice / 100;
        
        // Account for rounding up if there's a remainder
        uint256 remainder = expectedBasePrice % 100;
        if (remainder > 0) {
            expectedLdtAmount += 1;
        }
        
        assertEq(ldtAmount, expectedLdtAmount);
    }

    // Test very high decimal conversion (21 decimals)  
    function test_priceInToken_very_high_decimals() public view {
        uint256 duration = 365 days;
        string memory name = "testname";
        
        uint256 expectedBasePrice = PRICE_5_CHAR * duration;
        
        // HDT (21 decimals) - should be scaled up by 10^15
        uint256 hdtAmount = priceOracle.priceInToken(name, 0, duration, address(highDecimalToken));
        assertEq(hdtAmount, expectedBasePrice * 1e15);
    }

    // Test rounding up behavior with specific case
    function test_low_decimal_rounding_up() public view {
        // Use 1 second duration to create a remainder
        uint256 duration = 1;
        string memory name = "eth"; // 3 chars -> uses PRICE_3_CHAR
        
        uint256 basePrice = PRICE_3_CHAR * duration; // 20289
        uint256 ldtAmount = priceOracle.priceInToken(name, 0, duration, address(lowDecimalToken));
        
        // 20289 / 100 = 202 remainder 89, should round up to 203
        assertEq(ldtAmount, 203);
        
        // Verify the calculation manually
        uint256 quotient = basePrice / 100; // 202
        uint256 remainder = basePrice % 100; // 89
        assertEq(quotient, 202);
        assertEq(remainder, 89);
        assertGt(remainder, 0, "Should have remainder to test rounding");
    }

    // Test token configuration
    function test_getTokenConfig() public {
        // Test supported token
        ITokenPriceOracle.TokenConfig memory usdcConfig = priceOracle.getTokenConfig(address(usdc));
        assertTrue(usdcConfig.enabled);
        assertEq(usdcConfig.decimals, 6);
        
        // Test unsupported token
        MockERC20 unsupportedToken = new MockERC20("UNS", "UNS", 8);
        ITokenPriceOracle.TokenConfig memory unsupportedConfig = priceOracle.getTokenConfig(address(unsupportedToken));
        assertFalse(unsupportedConfig.enabled);
        assertEq(unsupportedConfig.decimals, 0);
    }

    // Test unsupported token reverts
    function test_Revert_unsupported_token() public {
        MockERC20 unsupportedToken = new MockERC20("UNS", "UNS", 8);
        
        vm.expectRevert(abi.encodeWithSelector(ITokenPriceOracle.TokenNotSupported.selector, address(unsupportedToken)));
        priceOracle.priceInToken("test", 0, 365 days, address(unsupportedToken));
    }

    // Test constructor validations
    function test_Revert_invalid_rent_prices_length() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        
        uint8[] memory decimals = new uint8[](1);
        decimals[0] = 6;
        
        // Wrong number of rent prices (should be 5)
        uint256[] memory wrongRentPrices = new uint256[](3);
        wrongRentPrices[0] = PRICE_5_CHAR;
        wrongRentPrices[1] = PRICE_4_CHAR;
        wrongRentPrices[2] = PRICE_3_CHAR;
        
        vm.expectRevert(abi.encodeWithSelector(StablePriceOracle.InvalidRentPricesLength.selector));
        new StablePriceOracle(tokens, decimals, wrongRentPrices);
    }
}