// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../src/L2/ETHRegistrar.sol";
import "../src/L2/TokenPriceOracle.sol";
import "../src/common/PermissionedRegistry.sol";
import "../src/common/RegistryDatastore.sol";
import "../src/common/SimpleRegistryMetadata.sol";
import {LibEACBaseRoles} from "../src/common/EnhancedAccessControl.sol";
import {LibRegistryRoles} from "../src/common/LibRegistryRoles.sol";

/**
 * @title ETHRegistrar Operational Risk Tests
 * @notice Tests for real-world operational risks when using trusted tokens (USDC, USDT, DAI)
 * These tests focus on practical issues that could affect production deployment.
 */

// Mock USDC with blacklist functionality (similar to real USDC)
contract MockUSDCWithBlacklist is ERC20 {
    mapping(address => bool) public blacklisted;
    address public blacklister;
    
    constructor() ERC20("USD Coin", "USDC") {
        blacklister = msg.sender;
        _mint(msg.sender, 1000000 * 1e6);
    }
    
    function decimals() public pure override returns (uint8) {
        return 6;
    }
    
    function blacklist(address account) external {
        require(msg.sender == blacklister, "Not blacklister");
        blacklisted[account] = true;
    }
    
    function unblacklist(address account) external {
        require(msg.sender == blacklister, "Not blacklister");
        blacklisted[account] = false;
    }
    
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        require(!blacklisted[from], "Account blacklisted");
        require(!blacklisted[to], "Account blacklisted");
        return super.transferFrom(from, to, amount);
    }
}

// Mock USDT-like token that doesn't return values
contract MockUSDTNoReturn is ERC20 {
    constructor() ERC20("Tether USD", "USDT") {
        _mint(msg.sender, 1000000 * 1e6);
    }
    
    function decimals() public pure override returns (uint8) {
        return 6;
    }
    
    // USDT doesn't return bool on transferFrom
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        super.transferFrom(from, to, amount);
        // Simulate USDT by not returning anything (Solidity will return false)
        assembly {
            return(0, 0)
        }
    }
}

// Token that returns false on failure rather than reverting
contract MockTokenFalseReturn is ERC20 {
    bool public shouldFail;
    
    constructor() ERC20("False Return Token", "FALSE") {
        _mint(msg.sender, 1000000 * 1e18);
    }
    
    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }
    
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (shouldFail) {
            return false; // Return false rather than reverting
        }
        return super.transferFrom(from, to, amount);
    }
}

contract ETHRegistrarOperationalRisksTest is Test, ERC1155Holder {
    RegistryDatastore datastore;
    PermissionedRegistry registry;
    ETHRegistrar registrar;
    TokenPriceOracle priceOracle;
    
    MockUSDCWithBlacklist usdc;
    MockUSDTNoReturn usdt;
    MockTokenFalseReturn falseToken;
    
    address user = address(0x1234);
    address beneficiary = address(0x5678);
    address blacklister = address(0x9999);
    
    uint256 constant MIN_COMMITMENT_AGE = 60;
    uint256 constant MAX_COMMITMENT_AGE = 86400;
    uint256 constant ROLE_REGISTRAR = 1 << 0;
    uint256 constant ROLE_RENEW = 1 << 4;
    
    bytes32 constant SECRET = bytes32(uint256(12345));
    uint64 constant DURATION = 365 days;
    
    function setUp() public {
        vm.warp(2_000_000_000);
        
        // Deploy infrastructure
        datastore = new RegistryDatastore();
        registry = new PermissionedRegistry(datastore, new SimpleRegistryMetadata(), address(this), LibEACBaseRoles.ALL_ROLES);
        
        // Deploy mock tokens
        usdc = new MockUSDCWithBlacklist();
        usdt = new MockUSDTNoReturn();
        falseToken = new MockTokenFalseReturn();
        
        // Setup price oracle with all tokens
        address[] memory tokens = new address[](3);
        tokens[0] = address(usdc);
        tokens[1] = address(usdt);
        tokens[2] = address(falseToken);
        
        uint8[] memory decimals = new uint8[](3);
        decimals[0] = 6;  // USDC
        decimals[1] = 6;  // USDT
        decimals[2] = 18; // False token
        
        uint256[] memory rentPrices = new uint256[](1);
        rentPrices[0] = 10 * 1e6; // $10 in 6 decimals
        
        priceOracle = new TokenPriceOracle(tokens, decimals, rentPrices);
        
        // Deploy registrar
        registrar = new ETHRegistrar(
            address(registry),
            priceOracle,
            MIN_COMMITMENT_AGE,
            MAX_COMMITMENT_AGE,
            beneficiary
        );
        
        registry.grantRootRoles(LibRegistryRoles.ROLE_REGISTRAR | LibRegistryRoles.ROLE_RENEW, address(registrar));
        
        // Setup user with tokens
        usdc.transfer(user, 1000 * 1e6);
        usdt.transfer(user, 1000 * 1e6);
        falseToken.transfer(user, 1000 * 1e18);
        
        vm.startPrank(user);
        usdc.approve(address(registrar), type(uint256).max);
        usdt.approve(address(registrar), type(uint256).max);
        falseToken.approve(address(registrar), type(uint256).max);
        vm.stopPrank();
    }
    
    function test_user_blacklisted_cannot_renew() public {
        console.log("\n=== User Blacklisted - Cannot Renew Test ===");
        console.log("Real operational risk: User gets blacklisted by USDC after registering");
        
        vm.startPrank(user);
        
        // User successfully registers with USDC
        bytes32 commitment = registrar.makeCommitment("valuable", user, SECRET, address(registry), address(0), DURATION);
        registrar.commit(commitment);
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        console.log("1. User registers name with USDC...");
        registrar.register("valuable", user, SECRET, registry, address(0), DURATION, address(usdc));
        console.log("   [SUCCESS] Registration successful");
        
        vm.stopPrank();
        
        // User gets blacklisted by USDC (e.g., regulatory action)
        console.log("2. User gets blacklisted by USDC issuer...");
        usdc.blacklist(user);
        console.log("   [SUCCESS] User blacklisted");
        
        // user cannot renew their valuable name with USDC
        vm.startPrank(user);
        console.log("3. User attempts to renew name with USDC...");
        vm.expectRevert("Account blacklisted");
        registrar.renew("valuable", DURATION, address(usdc));
        console.log("   [FAIL] Renewal with USDC failed - user is blacklisted!");
        
        // But user can still renew with other tokens (like USDT)
        console.log("4. User attempts to renew with alternative token (USDT)...");
        registrar.renew("valuable", DURATION, address(usdt));
        console.log("   [SUCCESS] Renewal with USDT successful - user keeps their name!");
        
        vm.stopPrank();
        
        console.log("\n[INFO] Mitigation: Support multiple payment tokens for resilience");
    }
    
    function test_beneficiary_blacklisted_breaks_registrar() public {
        console.log("\n=== Beneficiary Blacklisted - Registrar Broken Test ===");
        console.log("Critical operational risk: If beneficiary gets blacklisted, entire registrar fails");
        
        vm.startPrank(user);
        
        // Make commitment
        bytes32 commitment = registrar.makeCommitment("test", user, SECRET, address(registry), address(0), DURATION);
        registrar.commit(commitment);
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        console.log("1. Normal registration works...");
        registrar.register("test", user, SECRET, registry, address(0), DURATION, address(usdc));
        console.log("   [SUCCESS] Registration successful");
        
        vm.stopPrank();
        
        // Beneficiary gets blacklisted (e.g., multisig flagged, contract issue)
        console.log("2. Beneficiary gets blacklisted by USDC...");
        usdc.blacklist(beneficiary);
        console.log("   [SUCCESS] Beneficiary blacklisted");
        
        // ALL registrations with USDC fail
        vm.startPrank(user);
        commitment = registrar.makeCommitment("blocked", user, SECRET, address(registry), address(0), DURATION);
        registrar.commit(commitment);
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        console.log("3. Any user attempts new registration with USDC...");
        vm.expectRevert("Account blacklisted");
        registrar.register("blocked", user, SECRET, registry, address(0), DURATION, address(usdc));
        console.log("   [FAIL] ALL registrations with USDC now fail!");
        
        console.log("4. Renewals with USDC also fail...");
        vm.expectRevert("Account blacklisted");
        registrar.renew("test", DURATION, address(usdc));
        console.log("   [FAIL] ALL renewals with USDC fail!");
        
        // But other tokens still work
        console.log("5. User tries registration with alternative token (USDT)...");
        commitment = registrar.makeCommitment("alternative", user, SECRET, address(registry), address(0), DURATION);
        registrar.commit(commitment);
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        registrar.register("alternative", user, SECRET, registry, address(0), DURATION, address(usdt));
        console.log("   [SUCCESS] Registration with USDT works!");
        
        console.log("6. Renewal with alternative token also works...");
        registrar.renew("alternative", DURATION, address(usdt));
        console.log("   [SUCCESS] Renewal with USDT works!");
        
        vm.stopPrank();        
    }
    
    function test_safeerc20_handles_usdt_no_return() public {
        console.log("\n=== SafeERC20 Handles USDT No Return Value ===");
        console.log("Validates that SafeERC20 properly handles USDT-style tokens");
        
        vm.startPrank(user);
        
        // Make commitment
        bytes32 commitment = registrar.makeCommitment("usdt-test", user, SECRET, address(registry), address(0), DURATION);
        registrar.commit(commitment);
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        uint256 balanceBefore = usdt.balanceOf(user);
        console.log("User USDT balance before:", balanceBefore);
        
        // Registration should work despite USDT not returning a value
        console.log("Registering with USDT (no return value)...");
        registrar.register("usdt-test", user, SECRET, registry, address(0), DURATION, address(usdt));
        
        uint256 balanceAfter = usdt.balanceOf(user);
        console.log("User USDT balance after:", balanceAfter);
        console.log("Payment made:", balanceBefore - balanceAfter);
        
        assertTrue(balanceBefore > balanceAfter, "Payment should have been made");
        assertTrue(!registrar.available("usdt-test"), "Name should be registered");
        console.log("[SUCCESS] SafeERC20 successfully handled USDT transfer");
        
        vm.stopPrank();
    }
    
    function test_safeerc20_prevents_false_return_exploit() public {
        console.log("\n=== SafeERC20 Prevents False Return Exploit ===");
        console.log("Validates that SafeERC20 catches tokens that return false rather than reverting");
        
        vm.startPrank(user);
        
        // Make commitment
        bytes32 commitment = registrar.makeCommitment("exploit", user, SECRET, address(registry), address(0), DURATION);
        registrar.commit(commitment);
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        // Set token to return false on transfer
        falseToken.setShouldFail(true);
        
        uint256 balanceBefore = falseToken.balanceOf(user);
        console.log("User balance before failed registration:", balanceBefore);
        
        // Registration should fail because SafeERC20 catches the false return
        console.log("Attempting registration with false-returning token...");
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(falseToken)));
        registrar.register("exploit", user, SECRET, registry, address(0), DURATION, address(falseToken));
        
        uint256 balanceAfter = falseToken.balanceOf(user);
        console.log("User balance after failed registration:", balanceAfter);
        
        assertEq(balanceBefore, balanceAfter, "No payment should have been made");
        assertTrue(registrar.available("exploit"), "Name should still be available");
        console.log("[SUCCESS] SafeERC20 successfully prevented false return exploit");
        
        vm.stopPrank();
    }
    
}