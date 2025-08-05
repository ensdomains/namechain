// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "../src/L2/StablePriceOracle.sol";
import "../src/L2/ETHRegistrar.sol";
import "../src/mocks/MockERC20.sol";
import "./mocks/MockPermissionedRegistry.sol";
import "../src/common/RegistryDatastore.sol";
import "../src/common/SimpleRegistryMetadata.sol";
import {LibEACBaseRoles} from "../src/common/EnhancedAccessControl.sol";
import {LibRegistryRoles} from "../src/common/LibRegistryRoles.sol";

contract TestStablePriceOracleIntegration is Test, ERC1155Holder {
    StablePriceOracle priceOracle;
    ETHRegistrar registrar;
    MockERC20 usdc;
    MockPermissionedRegistry registry;
    RegistryDatastore datastore;
    
    address user1 = address(0x1);
    address beneficiary = address(0x3);
    
    uint256 constant MIN_COMMITMENT_AGE = 60;
    uint256 constant MAX_COMMITMENT_AGE = 86400;
    
    uint64 constant YEAR = 365 days;
    
    // Ported from ENS ens-contracts TestStablePriceOracle.ts
    // Price Array: [0, 0, 4, 2, 1] (attousd per second by name length)
    uint256 constant PRICE_1_CHAR = 0; // 0 attousd/sec (not allowed)
    uint256 constant PRICE_2_CHAR = 0; // 0 attousd/sec (not allowed)
    uint256 constant PRICE_3_CHAR = 4; // 4 attousd/sec 
    uint256 constant PRICE_4_CHAR = 2; // 2 attousd/sec
    uint256 constant PRICE_5_CHAR = 1; // 1 attousd/sec (5+ chars)
    bytes32 constant SECRET = bytes32(uint256(1234567890));
    
    function setUp() public {
        vm.warp(2_000_000_000);
        
        // Setup token
        usdc = new MockERC20("USDC", "USDC", 6);
        
        // Setup StablePriceOracle
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        
        uint8[] memory decimals = new uint8[](1);
        decimals[0] = 6;
        
        uint256[] memory rentPrices = new uint256[](5);
        rentPrices[0] = PRICE_5_CHAR; // 5+ chars
        rentPrices[1] = PRICE_4_CHAR; // 4 chars
        rentPrices[2] = PRICE_3_CHAR; // 3 chars
        rentPrices[3] = PRICE_2_CHAR; // 2 chars (not supported)
        rentPrices[4] = PRICE_1_CHAR; // 1 char (not supported)
        
        priceOracle = new StablePriceOracle(tokens, decimals, rentPrices);
        
        // Setup registry
        datastore = new RegistryDatastore();
        uint256 deployerRoles = LibEACBaseRoles.ALL_ROLES;
        registry = new MockPermissionedRegistry(datastore, new SimpleRegistryMetadata(), address(this), deployerRoles);
        
        // Setup registrar with StablePriceOracle
        registrar = new ETHRegistrar(address(registry), priceOracle, MIN_COMMITMENT_AGE, MAX_COMMITMENT_AGE, beneficiary);
        registry.grantRootRoles(LibRegistryRoles.ROLE_REGISTRAR | LibRegistryRoles.ROLE_RENEW, address(registrar));
        
        // Mint tokens
        uint256 tokenAmount = 10000000 * 1e6; // 10M USDC
        usdc.mint(address(this), tokenAmount);
        usdc.mint(user1, tokenAmount);
        
        // Approve registrar
        usdc.approve(address(registrar), type(uint256).max);
        vm.prank(user1);
        usdc.approve(address(registrar), type(uint256).max);
    }
    
    function test_registration_with_length_based_pricing() public {
        // Test registering names of different lengths
        
        // Using ENS test names for consistency
        // 5+ character name: 1 attousd/sec
        _testRegistration("fubar", PRICE_5_CHAR * YEAR);
        
        // 4 character name: 2 attousd/sec
        _testRegistration("quux", PRICE_4_CHAR * YEAR);
        
        // 3 character name: 4 attousd/sec
        _testRegistration("foo", PRICE_3_CHAR * YEAR);
    }
    
    function test_multi_year_registration_pricing() public {
        string memory name = "alice";
        uint64 duration = 3 * YEAR; // 3 years
        
        // Check price
        uint256 expectedCost = PRICE_5_CHAR * duration;
        uint256 actualCost = registrar.checkPrice(name, duration, address(usdc));
        assertEq(actualCost, expectedCost, "3-year registration price incorrect");
        
        // Register for 3 years
        uint256 initialBalance = usdc.balanceOf(address(this));
        
        bytes32 commitment = registrar.makeCommitment(name, address(this), SECRET, address(registry), address(0), duration);
        registrar.commit(commitment);
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        registrar.register(name, address(this), SECRET, registry, address(0), duration, address(usdc));
        
        // Verify payment
        uint256 finalBalance = usdc.balanceOf(address(this));
        assertEq(initialBalance - finalBalance, expectedCost, "Incorrect payment amount");
    }
    
    function test_renewal_with_stable_pricing() public {
        string memory name = "test"; // 4 char name
        uint64 initialDuration = YEAR;
        uint64 renewalDuration = 2 * YEAR;
        
        // Register first
        bytes32 commitment = registrar.makeCommitment(name, address(this), SECRET, address(registry), address(0), initialDuration);
        registrar.commit(commitment);
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        uint256 tokenId = registrar.register(name, address(this), SECRET, registry, address(0), initialDuration, address(usdc));
        uint64 initialExpiry = registry.getExpiry(tokenId);
        
        // Check renewal price
        uint256 expectedRenewalCost = PRICE_4_CHAR * renewalDuration;
        uint256 actualRenewalCost = registrar.checkPrice(name, renewalDuration, address(usdc));
        assertEq(actualRenewalCost, expectedRenewalCost, "Renewal price incorrect");
        
        // Renew
        uint256 balanceBefore = usdc.balanceOf(address(this));
        registrar.renew(name, renewalDuration, address(usdc));
        uint256 balanceAfter = usdc.balanceOf(address(this));
        
        // Verify renewal
        uint64 newExpiry = registry.getExpiry(tokenId);
        assertEq(newExpiry, initialExpiry + renewalDuration, "Expiry not extended correctly");
        assertEq(balanceBefore - balanceAfter, expectedRenewalCost, "Incorrect renewal payment");
    }
    
    function test_unsupported_name_lengths() public {
        // 2 character name should fail (price is 0)
        string memory name2 = "ab";
        uint256 price2 = registrar.checkPrice(name2, YEAR, address(usdc));
        assertEq(price2, 0, "2-char name should have 0 price");
        
        // 1 character name should fail (price is 0)
        string memory name1 = "a";
        uint256 price1 = registrar.checkPrice(name1, YEAR, address(usdc));
        assertEq(price1, 0, "1-char name should have 0 price");
    }
    
    function test_beneficiary_receives_payments() public {
        string memory name = "premium"; // 7 char name
        uint64 duration = YEAR;
        uint256 expectedCost = PRICE_5_CHAR * duration;
        
        uint256 beneficiaryBalanceBefore = usdc.balanceOf(beneficiary);
        
        // Register
        bytes32 commitment = registrar.makeCommitment(name, address(this), SECRET, address(registry), address(0), duration);
        registrar.commit(commitment);
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        registrar.register(name, address(this), SECRET, registry, address(0), duration, address(usdc));
        
        uint256 beneficiaryBalanceAfter = usdc.balanceOf(beneficiary);
        assertEq(beneficiaryBalanceAfter - beneficiaryBalanceBefore, expectedCost, "Beneficiary didn't receive payment");
    }
    
    function _testRegistration(string memory name, uint256 expectedCost) internal {
        // Check price
        uint256 actualCost = registrar.checkPrice(name, YEAR, address(usdc));
        assertEq(actualCost, expectedCost, string.concat("Price mismatch for ", name));
        
        // Register
        uint256 initialBalance = usdc.balanceOf(address(this));
        
        bytes32 commitment = registrar.makeCommitment(name, address(this), SECRET, address(registry), address(0), YEAR);
        registrar.commit(commitment);
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        uint256 tokenId = registrar.register(name, address(this), SECRET, registry, address(0), YEAR, address(usdc));
        
        // Verify registration
        assertEq(registry.ownerOf(tokenId), address(this), "Incorrect owner");
        assertEq(registry.getExpiry(tokenId), uint64(block.timestamp + YEAR), "Incorrect expiry");
        
        // Verify payment
        uint256 finalBalance = usdc.balanceOf(address(this));
        assertEq(initialBalance - finalBalance, expectedCost, "Incorrect payment amount");
    }
}