// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "../src/L2/StablePriceOracle.sol";
import "../src/mocks/MockERC20.sol";
import {IPriceOracle} from "@ens/contracts/ethregistrar/IPriceOracle.sol";

contract TestStablePriceOracle is Test {
    StablePriceOracle priceOracle;
    MockERC20 usdc;
    
    uint256 constant PRICE_5_LETTER = 5 * 1e6; // $5 in 6 decimals
    uint256 constant PRICE_4_LETTER = 160 * 1e6; // $160 in 6 decimals  
    uint256 constant PRICE_3_LETTER = 640 * 1e6; // $640 in 6 decimals
    
    function setUp() public {
        usdc = new MockERC20("USDC", "USDC", 6);
        
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        
        uint8[] memory decimals = new uint8[](1);
        decimals[0] = 6;
        
        uint256[] memory rentPrices = new uint256[](5);
        rentPrices[0] = PRICE_5_LETTER; // 5+ chars
        rentPrices[1] = PRICE_4_LETTER; // 4 chars  
        rentPrices[2] = PRICE_3_LETTER; // 3 chars
        rentPrices[3] = 0; // 2 chars (not supported yet)
        rentPrices[4] = 0; // 1 char (not supported yet)
        
        priceOracle = new StablePriceOracle(tokens, decimals, rentPrices);
    }

    function test_inheritance() public view {
        assertTrue(address(priceOracle) != address(0));
    }
    
    function test_length_based_pricing() public view {
        uint256 duration = 365 days;
        
        // Test 5+ character pricing
        IPriceOracle.Price memory price5 = priceOracle.price("alice", 0, duration);
        assertEq(price5.base, PRICE_5_LETTER * duration);
        assertEq(price5.premium, 0);
        
        // Test 4 character pricing  
        IPriceOracle.Price memory price4 = priceOracle.price("test", 0, duration);
        assertEq(price4.base, PRICE_4_LETTER * duration);
        assertEq(price4.premium, 0);
        
        // Test 3 character pricing
        IPriceOracle.Price memory price3 = priceOracle.price("eth", 0, duration);
        assertEq(price3.base, PRICE_3_LETTER * duration);
        assertEq(price3.premium, 0);
        
        // Test unsupported lengths return 0
        IPriceOracle.Price memory price2 = priceOracle.price("ab", 0, duration);
        assertEq(price2.base, 0);
        assertEq(price2.premium, 0);
        
        IPriceOracle.Price memory price1 = priceOracle.price("a", 0, duration);
        assertEq(price1.base, 0);
        assertEq(price1.premium, 0);
    }

    function test_constructor_validation() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        
        uint8[] memory decimals = new uint8[](1);
        decimals[0] = 6;
        
        // Test with wrong number of rent prices (should be 5)
        uint256[] memory wrongRentPrices = new uint256[](3);
        wrongRentPrices[0] = PRICE_5_LETTER;
        wrongRentPrices[1] = PRICE_4_LETTER;
        wrongRentPrices[2] = PRICE_3_LETTER;
        
        vm.expectRevert(StablePriceOracle.InvalidRentPricesLength.selector);
        new StablePriceOracle(tokens, decimals, wrongRentPrices);
    }

    function test_duration_calculations() public view {
        // Test different durations
        uint256 oneYear = 365 days;
        uint256 twoYears = 2 * 365 days;
        uint256 sixMonths = 182.5 days;
        
        // 5 character name for 2 years
        IPriceOracle.Price memory price2y = priceOracle.price("alice", 0, twoYears);
        assertEq(price2y.base, PRICE_5_LETTER * twoYears);
        
        // 4 character name for 6 months
        IPriceOracle.Price memory price6m = priceOracle.price("test", 0, sixMonths);
        assertEq(price6m.base, PRICE_4_LETTER * sixMonths);
        
        // 3 character name for exactly 1 year
        IPriceOracle.Price memory price1y = priceOracle.price("xyz", 0, oneYear);
        assertEq(price1y.base, PRICE_3_LETTER * oneYear);
    }

    function test_edge_case_names() public view {
        uint256 duration = 365 days;
        
        // Empty name
        IPriceOracle.Price memory priceEmpty = priceOracle.price("", 0, duration);
        assertEq(priceEmpty.base, 0);
        
        // Very long name
        IPriceOracle.Price memory priceLong = priceOracle.price("verylongdomainnamethatexceedsanyreasonablelength", 0, duration);
        assertEq(priceLong.base, PRICE_5_LETTER * duration);
        
        // Unicode characters (counted as bytes)
        IPriceOracle.Price memory priceUnicode = priceOracle.price(unicode"🦄", 0, duration);
        assertEq(priceUnicode.base, PRICE_4_LETTER * duration); // 4 bytes for emoji
    }

    function test_token_conversion() public view {
        string memory name = "alice";
        uint256 duration = 365 days;
        
        // Test USDC conversion (6 decimals)
        uint256 usdcAmount = priceOracle.priceInToken(name, 0, duration, address(usdc));
        assertEq(usdcAmount, PRICE_5_LETTER * duration);
    }
}
