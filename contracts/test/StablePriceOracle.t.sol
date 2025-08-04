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
}
