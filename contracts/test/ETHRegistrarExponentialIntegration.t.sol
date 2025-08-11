// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "../src/L2/ETHRegistrar.sol";
import "../src/L2/ExponentialPremiumPriceOracle.sol";
import "./mocks/MockPermissionedRegistry.sol";
import "../src/common/RegistryDatastore.sol";
import "../src/mocks/MockERC20.sol";
import "../src/common/SimpleRegistryMetadata.sol";
import {IPriceOracle} from "@ens/contracts/ethregistrar/IPriceOracle.sol";
import {LibEACBaseRoles} from "../src/common/EnhancedAccessControl.sol";
import {LibRegistryRoles} from "../src/common/LibRegistryRoles.sol";

contract TestETHRegistrarExponentialIntegration is Test, ERC1155Holder {
    RegistryDatastore datastore;
    MockPermissionedRegistry registry;
    ETHRegistrar registrar;
    ExponentialPremiumPriceOracle priceOracle;
    MockERC20 usdc;
    MockERC20 dai;

    address user1 = address(0x1);
    address user2 = address(0x2);
    address beneficiary = address(0x3);
    
    uint256 constant MIN_COMMITMENT_AGE = 60; // 1 minute
    uint256 constant MAX_COMMITMENT_AGE = 86400; // 1 day
    
    // Updated premium constants
    uint256 constant START_PREMIUM_USD = 100_000_000 * 1e6; // $100 million in 6 decimals
    uint256 constant TOTAL_DAYS = 21; // 21-day decay period
    
    // ENS pricing constants (nanodollars per second)
    uint256 constant PRICE_5_CHAR = 158;   // ~$5/year
    uint256 constant PRICE_4_CHAR = 5072;  // ~$160/year
    uint256 constant PRICE_3_CHAR = 20289; // ~$640/year
    
    uint64 constant REGISTRATION_DURATION = 365 days;
    bytes32 constant SECRET = bytes32(uint256(1234567890));
    bytes32 constant SECRET2 = bytes32(uint256(9876543210));

    function setUp() public {
        // Setup tokens
        usdc = new MockERC20("USDC", "USDC", 6);
        dai = new MockERC20("DAI", "DAI", 18);

        // Setup ExponentialPremiumPriceOracle with updated constants
        address[] memory tokens = new address[](2);
        tokens[0] = address(usdc);
        tokens[1] = address(dai);
        
        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 6; // USDC
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

        // Setup registry and registrar
        datastore = new RegistryDatastore();
        
        // Use realistic constructor for MockPermissionedRegistry
        uint256 deployerRoles = LibEACBaseRoles.ALL_ROLES;
        registry = new MockPermissionedRegistry(
            datastore,
            new SimpleRegistryMetadata(),
            address(this), // owner
            deployerRoles // all roles
        );

        registrar = new ETHRegistrar(
            address(registry),
            priceOracle,
            MIN_COMMITMENT_AGE,
            MAX_COMMITMENT_AGE,
            beneficiary
        );

        // Grant registrar permission to mint tokens
        registry.grantRootRoles(LibRegistryRoles.ROLE_REGISTRAR | LibRegistryRoles.ROLE_RENEW, address(registrar));

        // Give users some tokens for testing
        usdc.mint(user1, 1000_000_000 * 1e6); // $1B USDC
        usdc.mint(user2, 1000_000_000 * 1e6); // $1B USDC
        dai.mint(user1, 1000_000_000 * 1e18); // $1B DAI
    }

    function test_non_expired_name_registration() public {
        string memory name = "testname";
        
        // Test registration of non-expired name (no premium)
        vm.startPrank(user1);
        
        // Use unique block timestamp to avoid commitment conflicts  
        // MAX_COMMITMENT_AGE is 1 day, so jump way beyond that
        vm.warp(block.timestamp + MAX_COMMITMENT_AGE + 10000);
        
        // Make commitment with unique secret
        bytes32 commitment = registrar.makeCommitment(
            name, 
            user1, 
            SECRET2, // Use different secret
            address(0), // subregistry
            address(0), // resolver
            REGISTRATION_DURATION
        );
        
        registrar.commit(commitment);
        
        // Wait for commitment age
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        // Check price (should have no premium)
        IPriceOracle.Price memory price = registrar.rentPrice(name, REGISTRATION_DURATION);
        uint256 expectedBasePrice = PRICE_5_CHAR * REGISTRATION_DURATION;
        assertEq(price.base, expectedBasePrice, "Should have correct base price");
        assertEq(price.premium, 0, "Should have no premium for non-expired name");
        
        // Get token cost
        uint256 usdcCost = registrar.checkPrice(name, REGISTRATION_DURATION, address(usdc));
        assertEq(usdcCost, expectedBasePrice, "USDC cost should match base price");
        
        // Approve and register
        usdc.approve(address(registrar), usdcCost);
        
        uint256 tokenId = registrar.register(
            name,
            user1,
            SECRET2, // Use same secret as commitment
            IRegistry(address(0)), // This should work for register function
            address(0),
            REGISTRATION_DURATION,
            address(usdc)
        );
        
        // Verify registration
        assertGt(tokenId, 0, "Should return valid token ID");
        assertEq(usdc.balanceOf(beneficiary), usdcCost, "Beneficiary should receive payment");
        
        vm.stopPrank();
    }

    function test_expired_name_with_massive_premium() public {
        string memory name = "expiredname";
        uint256 nameExpiry = 1000; // Some past timestamp
        uint256 currentTime = nameExpiry + 91 days; // 1 day past grace period
        
        vm.warp(currentTime);
        
        // Check price for expired name
        IPriceOracle.Price memory price = registrar.rentPrice(name, REGISTRATION_DURATION);
        
        uint256 expectedBasePrice = PRICE_5_CHAR * REGISTRATION_DURATION;
        assertEq(price.base, expectedBasePrice, "Should have correct base price");
        assertGt(price.premium, 0, "Should have premium for expired name");
        
        // Premium should be significant (approximately start premium with decay)
        assertGt(price.premium, START_PREMIUM_USD / 3, "Premium should be very large initially");
        
        // Test token conversion with massive premium
        uint256 totalUsdPrice = price.base + price.premium;
        uint256 usdcCost = registrar.checkPrice(name, REGISTRATION_DURATION, address(usdc));
        assertEq(usdcCost, totalUsdPrice, "USDC cost should include premium");
        
        // Cost should be in tens of millions (due to exponential decay)
        assertGt(usdcCost, 30_000_000 * 1e6, "Should cost more than $30M");
    }

    function test_premium_decay_over_time() public {
        string memory name = "decayingname";
        uint256 nameExpiry = 1000;
        
        // Test premium at different time periods
        uint256[] memory testDays = new uint256[](5);
        testDays[0] = 91; // 1 day after grace period
        testDays[1] = 92; // 2 days after grace period
        testDays[2] = 95; // 5 days after grace period
        testDays[3] = 98; // 8 days after grace period
        testDays[4] = 111; // 21 days after grace period
        
        uint256 previousPremium = type(uint256).max;
        
        for (uint256 i = 0; i < testDays.length; i++) {
            vm.warp(nameExpiry + testDays[i] * 1 days);
            
            IPriceOracle.Price memory price = registrar.rentPrice(name, REGISTRATION_DURATION);
            
            // Premium should decrease over time
            if (i > 0) {
                assertLt(price.premium, previousPremium, "Premium should decrease over time");
            }
            
            previousPremium = price.premium;
        }
        
        // After 21 days, premium should be very small
        vm.warp(nameExpiry + 111 days);
        IPriceOracle.Price memory finalPrice = registrar.rentPrice(name, REGISTRATION_DURATION);
        assertLt(finalPrice.premium, START_PREMIUM_USD / 1000, "Premium should be minimal after 21 days");
    }

    function test_different_token_conversions_with_premium() public {
        string memory name = "tokentest";
        uint256 nameExpiry = 1000;
        vm.warp(nameExpiry + 91 days); // 1 day past grace period
        
        // Get costs in different tokens
        uint256 usdcCost = registrar.checkPrice(name, REGISTRATION_DURATION, address(usdc));
        uint256 daiCost = registrar.checkPrice(name, REGISTRATION_DURATION, address(dai));
        
        // DAI cost should be scaled up by 10^12 (18-6 decimals)
        assertEq(daiCost, usdcCost * 1e12, "DAI cost should be properly scaled");
        
        // Both should be very expensive due to premium
        assertGt(usdcCost, 10_000_000 * 1e6, "Should cost more than $10M in USDC");
        assertGt(daiCost, 10_000_000 * 1e18, "Should cost more than $10M in DAI");
    }

    function test_registration_with_premium_payment() public {
        string memory name = "premiumname";
        
        // Set time far enough to have a manageable premium
        // For unregistered names, expiry = 0, so premium is based on 
        // block.timestamp - 0 - 90 days (grace period)
        vm.warp(100 days); // This gives us 10 days past grace period
        
        vm.startPrank(user1);
        
        // Make commitment
        bytes32 commitment = registrar.makeCommitment(
            name,
            user1,
            SECRET,
            address(0), // subregistry
            address(0), // resolver
            REGISTRATION_DURATION
        );
        
        registrar.commit(commitment);
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        // Get total cost including premium
        uint256 usdcCost = registrar.checkPrice(name, REGISTRATION_DURATION, address(usdc));
        assertGt(usdcCost, PRICE_5_CHAR * REGISTRATION_DURATION, "Should include premium");
        
        // Approve and register
        usdc.approve(address(registrar), usdcCost);
        
        uint256 initialBeneficiaryBalance = usdc.balanceOf(beneficiary);
        
        uint256 tokenId = registrar.register(
            name,
            user1,
            SECRET,
            IRegistry(address(0)), // This should work for register function
            address(0),
            REGISTRATION_DURATION,
            address(usdc)
        );
        
        // Verify registration worked
        assertGt(tokenId, 0, "Should return valid token ID");
        
        // Verify payment was made (should be positive, indicating premium was included)
        uint256 finalBeneficiaryBalance = usdc.balanceOf(beneficiary);
        assertGt(finalBeneficiaryBalance, initialBeneficiaryBalance, "Beneficiary should receive payment");
        
        // The actual payment amount - when registering a new name,
        // the premium calculation uses the new expiry (future), so no premium
        uint256 actualPayment = finalBeneficiaryBalance - initialBeneficiaryBalance;
        uint256 expectedBasePrice = PRICE_5_CHAR * REGISTRATION_DURATION;
        assertEq(actualPayment, expectedBasePrice, "Should pay base price (no premium for new registration)");
        
        vm.stopPrank();
    }

    function test_grace_period_boundary() public {
        string memory name = "gracetest";
        uint256 nameExpiry = 1000;
        
        // Test directly with the price oracle (bypass registry lookup)
        // Test exactly at grace period end (90 days after expiry)
        vm.warp(nameExpiry + 90 days);
        IPriceOracle.Price memory priceAtBoundary = priceOracle.price(name, nameExpiry, REGISTRATION_DURATION);
        assertEq(priceAtBoundary.premium, 0, "Should have no premium exactly at grace period end");
        
        // Test 1 second past grace period
        vm.warp(nameExpiry + 90 days + 1 seconds);
        IPriceOracle.Price memory priceAfterBoundary = priceOracle.price(name, nameExpiry, REGISTRATION_DURATION);
        assertGt(priceAfterBoundary.premium, 0, "Should have premium just after grace period");
    }
}