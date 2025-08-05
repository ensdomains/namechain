// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "../src/L2/StablePriceOracle.sol";
import "../src/mocks/MockERC20.sol";
import {IPriceOracle} from "@ens/contracts/ethregistrar/IPriceOracle.sol";

contract TestStablePriceOracle is Test {
    StablePriceOracle priceOracle;
    MockERC20 usdc;
    
    // Ported test testing logic from https://github.com/ensdomains/ens-contracts/blob/staging/test/ethregistrar/TestStablePriceOracle.ts
    // Price Array: [0, 0, 4, 2, 1] (attousd per second by name length)
    // - Index 0-1: 0 attousd/sec (1-2 char names - not allowed)  
    // - Index 2: 4 attousd/sec (3 char names)
    // - Index 3: 2 attousd/sec (4 char names)
    // - Index 4: 1 attousd/sec (5+ char names)
    uint256 constant PRICE_1_CHAR = 0; // 0 attousd/sec (not allowed)
    uint256 constant PRICE_2_CHAR = 0; // 0 attousd/sec (not allowed)
    uint256 constant PRICE_3_CHAR = 4; // 4 attousd/sec 
    uint256 constant PRICE_4_CHAR = 2; // 2 attousd/sec
    uint256 constant PRICE_5_CHAR = 1; // 1 attousd/sec (5+ chars)
    
    function setUp() public {
        usdc = new MockERC20("USDC", "USDC", 6);
        
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        
        uint8[] memory decimals = new uint8[](1);
        decimals[0] = 6;
        
        // Price array matching ENS: [1char, 2char, 3char, 4char, 5+char]
        uint256[] memory rentPrices = new uint256[](5);
        rentPrices[0] = PRICE_5_CHAR; // 5+ chars (index 4 in ENS becomes index 0)
        rentPrices[1] = PRICE_4_CHAR; // 4 chars (index 3 in ENS becomes index 1)  
        rentPrices[2] = PRICE_3_CHAR; // 3 chars (index 2 in ENS becomes index 2)
        rentPrices[3] = PRICE_2_CHAR; // 2 chars (index 1 in ENS becomes index 3)
        rentPrices[4] = PRICE_1_CHAR; // 1 char (index 0 in ENS becomes index 4)
        
        priceOracle = new StablePriceOracle(tokens, decimals, rentPrices);
    }  

    function test_should_return_correct_prices() public view {
        uint256 oneHour = 3600; // 1 hour duration
        
        // Test Name: 'foo' (3 characters, 1 hour duration)
        // Expected: 4 attousd/sec × 3600 seconds = 14400 attousd
        IPriceOracle.Price memory priceFoo = priceOracle.price("foo", 0, oneHour);
        assertEq(priceFoo.base, PRICE_3_CHAR * oneHour, "foo (3 chars) pricing incorrect");
        assertEq(priceFoo.premium, 0);
        
        // Test Name: 'quux' (4 characters, 1 hour duration)  
        // Expected: 2 attousd/sec × 3600 seconds = 7200 attousd
        IPriceOracle.Price memory priceQuux = priceOracle.price("quux", 0, oneHour);
        assertEq(priceQuux.base, PRICE_4_CHAR * oneHour, "quux (4 chars) pricing incorrect");
        assertEq(priceQuux.premium, 0);
        
        // Test Name: 'fubar' (5 characters, 1 hour duration)
        // Expected: 1 attousd/sec × 3600 seconds = 3600 attousd  
        IPriceOracle.Price memory priceFubar = priceOracle.price("fubar", 0, oneHour);
        assertEq(priceFubar.base, PRICE_5_CHAR * oneHour, "fubar (5 chars) pricing incorrect");
        assertEq(priceFubar.premium, 0);
        
        // Test Name: 'foobie' (6 characters, 1 hour duration)
        // Expected: 1 attousd/sec × 3600 seconds = 3600 attousd (same as 5+ chars)
        IPriceOracle.Price memory priceFoobie = priceOracle.price("foobie", 0, oneHour);  
        assertEq(priceFoobie.base, PRICE_5_CHAR * oneHour, "foobie (6+ chars) should use 5+ char pricing");
        assertEq(priceFoobie.premium, 0);
        
        // Test unsupported lengths return 0
        IPriceOracle.Price memory price2 = priceOracle.price("ab", 0, oneHour);
        assertEq(price2.base, 0, "2 char names should return 0");
        assertEq(price2.premium, 0);
        
        IPriceOracle.Price memory price1 = priceOracle.price("a", 0, oneHour);
        assertEq(price1.base, 0, "1 char names should return 0");
        assertEq(price1.premium, 0);
    }

    function test_constructor_validation() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        
        uint8[] memory decimals = new uint8[](1);
        decimals[0] = 6;
        
        // Test with wrong number of rent prices (should be 5)
        uint256[] memory wrongRentPrices = new uint256[](3);
        wrongRentPrices[0] = PRICE_5_CHAR;
        wrongRentPrices[1] = PRICE_4_CHAR;
        wrongRentPrices[2] = PRICE_3_CHAR;
        
        vm.expectRevert(StablePriceOracle.InvalidRentPricesLength.selector);
        new StablePriceOracle(tokens, decimals, wrongRentPrices);
    }

    function test_should_work_with_larger_values() public {
        // Create oracle with extremely high pricing for 3-char names
        // Price Array: [0, 0, 1000000000000000000, 2, 1] (1 USD/second for 3-char names!)
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        
        uint8[] memory decimals = new uint8[](1);
        decimals[0] = 6;
        
        uint256[] memory rentPrices = new uint256[](5);
        rentPrices[0] = 1; // 5+ chars 
        rentPrices[1] = 2; // 4 chars
        rentPrices[2] = 1000000000000000000; // 3 chars - 1 USD/second!
        rentPrices[3] = 0; // 2 chars
        rentPrices[4] = 0; // 1 char
        
        StablePriceOracle bigOracle = new StablePriceOracle(tokens, decimals, rentPrices);
        
        // Test Name: 'foo' (3 characters, 24 hours duration)
        // Expected: 1 USD/second × 86400 seconds = $86,400
        uint256 twentyFourHours = 86400; // 24 hours in seconds
        IPriceOracle.Price memory price = bigOracle.price("foo", 0, twentyFourHours);
        
        uint256 expected = 1000000000000000000 * twentyFourHours; // 1 USD/sec × 86400 sec
        assertEq(price.base, expected, "Large value calculation should work correctly");
        assertEq(price.premium, 0);
    }
}
