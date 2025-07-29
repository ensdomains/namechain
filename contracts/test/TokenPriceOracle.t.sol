// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "../src/L2/TokenPriceOracle.sol";
import "../src/mocks/MockERC20.sol";

contract TestTokenPriceOracle is Test {
    TokenPriceOracle priceOracle;
    MockERC20 usdc;
    MockERC20 dai;
    MockERC20 wbtc;
    
    uint256 constant BASE_PRICE_USD = 10 * 1e6; // $10 in 6 decimals
    
    function setUp() public {
        // Create mock tokens with different decimals
        usdc = new MockERC20("USDC", "USDC", 6);
        dai = new MockERC20("DAI", "DAI", 18);
        wbtc = new MockERC20("WBTC", "WBTC", 8); // Bitcoin has 8 decimals
        
        // Setup TokenPriceOracle with initial tokens
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(dai);
        
        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 6;
        decimals[1] = 18;
        
        uint256[] memory rentPrices = new uint256[](1);
        rentPrices[0] = BASE_PRICE_USD;
        
        priceOracle = new TokenPriceOracle(tokens, decimals, rentPrices);
    }
    
    function test_constructor_array_length_mismatch() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(dai);
        
        uint8[] memory decimals = new uint8[](1); // Mismatched length
        decimals[0] = 6;
        
        uint256[] memory rentPrices = new uint256[](1);
        rentPrices[0] = BASE_PRICE_USD;
        
        vm.expectRevert(abi.encodeWithSelector(TokenPriceOracle.ArrayLengthMismatch.selector));
        new TokenPriceOracle(tokens, decimals, rentPrices);
    }
    
    function test_constructor_empty_rent_prices() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        
        uint8[] memory decimals = new uint8[](1);
        decimals[0] = 6;
        
        uint256[] memory rentPrices = new uint256[](0); // Empty array
        
        vm.expectRevert(abi.encodeWithSelector(TokenPriceOracle.EmptyRentPrices.selector));
        new TokenPriceOracle(tokens, decimals, rentPrices);
    }
    
    function test_isTokenSupported() public view {
        assertTrue(priceOracle.isTokenSupported(address(usdc)));
        assertTrue(priceOracle.isTokenSupported(address(dai)));
        assertFalse(priceOracle.isTokenSupported(address(wbtc))); // Not added in constructor
        assertFalse(priceOracle.isTokenSupported(address(0)));
    }
    
    function test_getTokenConfig() public view {
        TokenPriceOracle.TokenConfig memory usdcConfig = priceOracle.getTokenConfig(address(usdc));
        assertEq(usdcConfig.decimals, 6);
        assertTrue(usdcConfig.enabled);
        
        TokenPriceOracle.TokenConfig memory daiConfig = priceOracle.getTokenConfig(address(dai));
        assertEq(daiConfig.decimals, 18);
        assertTrue(daiConfig.enabled);
        
        // Test unsupported token returns default config
        TokenPriceOracle.TokenConfig memory wbtcConfig = priceOracle.getTokenConfig(address(wbtc));
        assertEq(wbtcConfig.decimals, 0);
        assertFalse(wbtcConfig.enabled);
    }
    
    function test_price() public view {
        string memory name = "example";
        uint256 expires = 0;
        uint256 duration = 365 days;
        
        IPriceOracle.Price memory price = priceOracle.price(name, expires, duration);
        assertEq(price.base, BASE_PRICE_USD);
        assertEq(price.premium, 0); // Default implementation returns 0 premium
    }
    
    function test_priceInToken_unsupported_token() public {
        string memory name = "example";
        uint256 expires = 0;
        uint256 duration = 365 days;
        
        vm.expectRevert(abi.encodeWithSelector(TokenPriceOracle.TokenNotSupported.selector, address(wbtc)));
        priceOracle.priceInToken(name, expires, duration, address(wbtc));
    }
    
    function test_priceInToken_different_decimals() public view {
        string memory name = "example";
        uint256 expires = 0;
        uint256 duration = 365 days;
        
        // USDC (6 decimals): $10 should be 10 * 10^6
        uint256 usdcAmount = priceOracle.priceInToken(name, expires, duration, address(usdc));
        assertEq(usdcAmount, 10 * 1e6);
        
        // DAI (18 decimals): $10 should be 10 * 10^18
        uint256 daiAmount = priceOracle.priceInToken(name, expires, duration, address(dai));
        assertEq(daiAmount, 10 * 1e18);
    }
    
    function test_convertUsdToToken_low_decimals_rounding() public {
        // Test with 2 decimal token (like some stablecoins)
        address[] memory tokens = new address[](1);
        tokens[0] = address(0x1);
        
        uint8[] memory decimals = new uint8[](1);
        decimals[0] = 2; // Very low decimals
        
        uint256[] memory rentPrices = new uint256[](1);
        rentPrices[0] = 1234567; // $1.234567 in 6 decimals
        
        TokenPriceOracle oracle = new TokenPriceOracle(tokens, decimals, rentPrices);
        
        // Should round up: 1234567 / 10000 = 123.4567, rounds up to 124
        uint256 tokenAmount = oracle.priceInToken("test", 0, 365 days, address(0x1));
        assertEq(tokenAmount, 124); // Rounded up
    }
    
    function test_convertUsdToToken_overflow_protection() public {
        // Test with extremely high decimal token to trigger overflow protection
        address[] memory tokens = new address[](1);
        tokens[0] = address(0x1);
        
        uint8[] memory decimals = new uint8[](1);
        decimals[0] = 77; // Very high decimals that would cause overflow
        
        uint256[] memory rentPrices = new uint256[](1);
        rentPrices[0] = type(uint256).max / 1e70; // Large value that would overflow with 77 decimals
        
        TokenPriceOracle oracle = new TokenPriceOracle(tokens, decimals, rentPrices);
        
        // Should revert due to overflow protection
        vm.expectRevert("TokenPriceOracle: Amount too large for token decimals");
        oracle.priceInToken("test", 0, 365 days, address(0x1));
    }
    
    function test_supportsInterface() public view {
        assertTrue(priceOracle.supportsInterface(type(IPriceOracle).interfaceId));
        assertTrue(priceOracle.supportsInterface(type(IERC165).interfaceId));
        assertFalse(priceOracle.supportsInterface(0x12345678)); // Random interface
    }
    
    function test_rentPrices_storage() public view {
        assertEq(priceOracle.rentPrices(0), BASE_PRICE_USD);
    }
    
    function test_multiple_rent_prices() public {
        // Setup oracle with multiple rent prices (e.g., for different name lengths)
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        
        uint8[] memory decimals = new uint8[](1);
        decimals[0] = 6;
        
        uint256[] memory rentPrices = new uint256[](3);
        rentPrices[0] = 100 * 1e6; // $100 for 3-char names
        rentPrices[1] = 50 * 1e6;  // $50 for 4-char names
        rentPrices[2] = 10 * 1e6;  // $10 for 5+ char names
        
        TokenPriceOracle oracle = new TokenPriceOracle(tokens, decimals, rentPrices);
        
        assertEq(oracle.rentPrices(0), 100 * 1e6);
        assertEq(oracle.rentPrices(1), 50 * 1e6);
        assertEq(oracle.rentPrices(2), 10 * 1e6);
    }
}

// Test custom implementation of TokenPriceOracle
contract CustomPriceOracle is TokenPriceOracle {
    constructor(
        address[] memory _tokens,
        uint8[] memory _decimals,
        uint256[] memory _rentPrices
    ) TokenPriceOracle(_tokens, _decimals, _rentPrices) {}
    
    // Override to implement length-based pricing
    function _base(string calldata name, uint256 /* duration */) 
        internal 
        view 
        override 
        returns (uint256) 
    {
        uint256 len = bytes(name).length;
        if (len == 3 && rentPrices.length > 0) return rentPrices[0];
        if (len == 4 && rentPrices.length > 1) return rentPrices[1];
        if (rentPrices.length > 2) return rentPrices[2];
        return rentPrices[0]; // Default to first price
    }
    
    // Override to implement exponential decay premium
    function _premium(string calldata /* name */, uint256 expires, uint256 /* duration */) 
        internal 
        view 
        override 
        returns (uint256) 
    {
        if (expires < block.timestamp) {
            // Name is expired, calculate premium based on time since expiry
            uint256 timeSinceExpiry = block.timestamp - expires;
            if (timeSinceExpiry < 30 days) {
                // High premium for recently expired names
                return 100 * 1e6; // $100 premium
            } else if (timeSinceExpiry < 90 days) {
                // Medium premium
                return 50 * 1e6; // $50 premium
            }
        }
        return 0; // No premium for non-expired or long-expired names
    }
}

contract TestCustomPriceOracle is Test {
    CustomPriceOracle customOracle;
    address usdc = address(0x1);
    
    function setUp() public {
        address[] memory tokens = new address[](1);
        tokens[0] = usdc;
        
        uint8[] memory decimals = new uint8[](1);
        decimals[0] = 6;
        
        uint256[] memory rentPrices = new uint256[](3);
        rentPrices[0] = 100 * 1e6; // $100 for 3-char
        rentPrices[1] = 50 * 1e6;  // $50 for 4-char
        rentPrices[2] = 10 * 1e6;  // $10 for 5+ char
        
        customOracle = new CustomPriceOracle(tokens, decimals, rentPrices);
    }
    
    function test_custom_length_based_pricing() public view {
        uint256 duration = 365 days;
        
        // 3-char name
        IPriceOracle.Price memory price3 = customOracle.price("abc", 0, duration);
        assertEq(price3.base, 100 * 1e6);
        
        // 4-char name
        IPriceOracle.Price memory price4 = customOracle.price("test", 0, duration);
        assertEq(price4.base, 50 * 1e6);
        
        // 5+ char name
        IPriceOracle.Price memory price5 = customOracle.price("example", 0, duration);
        assertEq(price5.base, 10 * 1e6);
    }
    
    function test_custom_premium_calculation() public {
        uint256 duration = 365 days;
        
        // Set a specific timestamp to avoid underflow
        vm.warp(1_000_000_000); // Set to a safe timestamp
        uint256 currentTime = block.timestamp;
        
        // Recently expired (10 days ago)
        uint256 recentExpiry = currentTime - 10 days;
        IPriceOracle.Price memory recentPrice = customOracle.price("test", recentExpiry, duration);
        assertEq(recentPrice.premium, 100 * 1e6); // $100 premium
        
        // Medium expired (60 days ago)
        uint256 mediumExpiry = currentTime - 60 days;
        IPriceOracle.Price memory mediumPrice = customOracle.price("test", mediumExpiry, duration);
        assertEq(mediumPrice.premium, 50 * 1e6); // $50 premium
        
        // Long expired (120 days ago)
        uint256 longExpiry = currentTime - 120 days;
        IPriceOracle.Price memory longPrice = customOracle.price("test", longExpiry, duration);
        assertEq(longPrice.premium, 0); // No premium
        
        // Not expired (future expiry)
        uint256 futureExpiry = currentTime + 100 days;
        IPriceOracle.Price memory futurePrice = customOracle.price("test", futureExpiry, duration);
        assertEq(futurePrice.premium, 0); // No premium
    }
}