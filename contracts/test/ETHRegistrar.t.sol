// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "../src/L2/ETHRegistrar.sol";
import "../src/L2/StablePriceOracle.sol";
import "./mocks/MockPermissionedRegistry.sol";
import "../src/common/RegistryDatastore.sol";
import {IPriceOracle} from "@ens/contracts/ethregistrar/IPriceOracle.sol";
import "../src/common/SimpleRegistryMetadata.sol";
import "../src/common/EnhancedAccessControl.sol";
import {LibEACBaseRoles} from "../src/common/EnhancedAccessControl.sol";
import "../src/common/NameUtils.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {LibRegistryRoles} from "../src/common/LibRegistryRoles.sol";

contract TestETHRegistrar is Test, ERC1155Holder {
    RegistryDatastore datastore;
    MockPermissionedRegistry registry;
    ETHRegistrar registrar;
    StablePriceOracle priceOracle;
    MockERC20 usdc;
    MockERC20 dai;

    address user1 = address(0x1);
    address user2 = address(0x2);
    address beneficiary = address(0x3);
    uint256 constant MIN_COMMITMENT_AGE = 60; // 1 minute
    uint256 constant MAX_COMMITMENT_AGE = 86400; // 1 day
    // Realistic ENS pricing from https://docs.ens.domains/registry/eth 
    // Using per-second rates calculated with high precision to avoid rounding to zero
    // 5+ character names: $5/year ÷ 31,536,000 seconds = ~158.5 × 10^-9 USD/sec
    // 4 character names: $160/year ÷ 31,536,000 seconds = ~5.072 × 10^-6 USD/sec  
    // 3 character names: $640/year ÷ 31,536,000 seconds = ~20.289 × 10^-6 USD/sec
    
    // Scale up to avoid integer division rounding to zero
    // Using nanodollars per second (1e9 scaling) then converting to 6-decimal USD
    uint256 constant PRICE_5_CHAR = 158; // ~158.5 nanodollars/sec → multiply by duration to get total 
    uint256 constant PRICE_4_CHAR = 5072; // ~5072 nanodollars/sec
    uint256 constant PRICE_3_CHAR = 20289; // ~20289 nanodollars/sec
    uint64 constant REGISTRATION_DURATION = 365 days;
    bytes32 constant SECRET = bytes32(uint256(1234567890));

    // Hardcoded role constants
    uint256 constant ROLE_REGISTRAR = 1 << 0;
    uint256 constant ROLE_RENEW = 1 << 4;
    bytes32 constant ROOT_RESOURCE = 0;

    function setUp() public {
        // Set the timestamp to a future date to avoid timestamp related issues
        vm.warp(2_000_000_000);

        // Create mock tokens
        usdc = new MockERC20("USDC", "USDC", 6);
        dai = new MockERC20("DAI", "DAI", 18);

        // Setup StablePriceOracle with length-based pricing
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
        
        priceOracle = new StablePriceOracle(tokens, decimals, rentPrices);

        // Setup registry and registrar
        datastore = new RegistryDatastore();
        // Use a defined ALL_ROLES value for deployer roles
        uint256 deployerRoles = LibEACBaseRoles.ALL_ROLES;
        registry = new MockPermissionedRegistry(datastore, new SimpleRegistryMetadata(), address(this), deployerRoles);
        registrar = new ETHRegistrar(address(registry), priceOracle, MIN_COMMITMENT_AGE, MAX_COMMITMENT_AGE, beneficiary);
        registry.grantRootRoles(LibRegistryRoles.ROLE_REGISTRAR | LibRegistryRoles.ROLE_RENEW, address(registrar));
        
        // Mint tokens to test accounts
        uint256 tokenAmount = 1000000 * 1e6; // 1M USDC
        usdc.mint(address(this), tokenAmount);
        usdc.mint(user1, tokenAmount);
        usdc.mint(user2, tokenAmount);
        
        uint256 daiAmount = 1000000 * 1e18; // 1M DAI
        dai.mint(address(this), daiAmount);
        dai.mint(user1, daiAmount);
        dai.mint(user2, daiAmount);

        // Approve registrar to spend tokens
        usdc.approve(address(registrar), type(uint256).max);
        dai.approve(address(registrar), type(uint256).max);
        
        vm.prank(user1);
        usdc.approve(address(registrar), type(uint256).max);
        vm.prank(user1);
        dai.approve(address(registrar), type(uint256).max);
        
        vm.prank(user2);
        usdc.approve(address(registrar), type(uint256).max);
        vm.prank(user2);
        dai.approve(address(registrar), type(uint256).max);
    }


    // Helper function to register a name with USDC (default test token)
    function _registerName(
        string memory name,
        address owner,
        bytes32 secret,
        IRegistry subregistry,
        address resolver,
        uint64 duration
    ) internal returns (uint256 tokenId) {
        bytes32 commitment = registrar.makeCommitment(name, owner, secret, address(subregistry), resolver, duration);
        registrar.commit(commitment);
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        tokenId = registrar.register(name, owner, secret, subregistry, resolver, duration, address(usdc));
    }

    function test_valid() public view {
        assertTrue(registrar.valid("abc"));
        assertTrue(registrar.valid("test"));
        assertTrue(registrar.valid("longername"));
        
        assertFalse(registrar.valid("ab"));
        assertFalse(registrar.valid("a"));
        assertFalse(registrar.valid(""));
    }

    function test_Revert_maxCommitmentAgeTooLow() public {
        // Try to create a registrar with maxCommitmentAge <= minCommitmentAge
        uint256 invalidMinAge = 100;
        uint256 invalidMaxAge = 100; // Equal to minAge, should revert
        
        vm.expectRevert(abi.encodeWithSelector(ETHRegistrar.MaxCommitmentAgeTooLow.selector));
        new ETHRegistrar(address(registry), priceOracle, invalidMinAge, invalidMaxAge, beneficiary);
        // Try with max age less than min age
        invalidMaxAge = 99; // Less than minAge, should revert
        
        vm.expectRevert(abi.encodeWithSelector(ETHRegistrar.MaxCommitmentAgeTooLow.selector));
        new ETHRegistrar(address(registry), priceOracle, invalidMinAge, invalidMaxAge, beneficiary);
    }

    function test_available() public {
        string memory name = "testname";
        assertTrue(registrar.available(name));
        
        // Register the name with USDC
        bytes32 commitment = registrar.makeCommitment(
            name, 
            address(this), 
            SECRET, 
            address(registry),
            address(0), // resolver
            REGISTRATION_DURATION
        );
        registrar.commit(commitment);
        
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        registrar.register(
            name, 
            address(this), 
            SECRET,
            registry,
            address(0), // resolver
            REGISTRATION_DURATION,
            address(usdc)
        );
        
        // Now the name should not be available
        assertFalse(registrar.available(name));
    }

    function test_rentPrice() public view {
        string memory name = "testname";
        IPriceOracle.Price memory price = registrar.rentPrice(name, REGISTRATION_DURATION);
        
        uint256 expectedPrice = PRICE_5_CHAR * REGISTRATION_DURATION;
        assertEq(price.base, expectedPrice);
        assertEq(price.premium, 0);
    }

    function test_checkPrice() public view {
        string memory name = "testname";
        
        uint256 expectedBasePrice = PRICE_5_CHAR * REGISTRATION_DURATION;
        
        // Check USDC price (6 decimals) - should match base price since both use 6 decimals
        uint256 usdcAmount = registrar.checkPrice(name, REGISTRATION_DURATION, address(usdc));
        assertEq(usdcAmount, expectedBasePrice);
        
        // Check DAI price (18 decimals) - should be scaled up by 10^12
        uint256 daiAmount = registrar.checkPrice(name, REGISTRATION_DURATION, address(dai));
        assertEq(daiAmount, expectedBasePrice * 1e12);
    }

    function test_makeCommitment() public view {
        string memory name = "testname";
        address owner = address(this);
        bytes32 secret = bytes32(uint256(1));
        address subregistry = address(registry);
        address resolver = address(0);
        uint64 duration = REGISTRATION_DURATION;
        
        bytes32 commitment = registrar.makeCommitment(name, owner, secret, subregistry, resolver, duration);
        
        bytes32 expectedCommitment = keccak256(
            abi.encode(
                name,
                owner,
                secret,
                subregistry,
                resolver,
                duration
            )
        );
        
        assertEq(commitment, expectedCommitment);
    }

    function test_commit() public {
        string memory name = "testname";
        bytes32 commitment = registrar.makeCommitment(
            name, 
            address(this), 
            bytes32(0), 
            address(registry),
            address(0), // resolver
            REGISTRATION_DURATION
        );
        
        // Record logs to check for events
        vm.recordLogs();
        
        registrar.commit(commitment);
        
        // Check that the commitment was stored
        assertEq(registrar.commitments(commitment), block.timestamp);
        
        // Check for CommitmentMade event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundEvent = EventUtils.checkEvent(
            entries,
            keccak256("CommitmentMade(bytes32)")
        );
        
        assertTrue(foundEvent, "CommitmentMade event not emitted");
    }

    function test_Revert_unexpiredCommitment() public {
        string memory name = "testname";
        bytes32 commitment = registrar.makeCommitment(
            name, 
            address(this), 
            bytes32(0), 
            address(registry),
            address(0), // resolver
            REGISTRATION_DURATION
        );
        
        registrar.commit(commitment);
        
        // Try to commit again, should revert
        vm.expectRevert(abi.encodeWithSelector(ETHRegistrar.UnexpiredCommitmentExists.selector, commitment));
        registrar.commit(commitment);
    }

    function test_register() public {
        string memory name = "testname";
        address owner = address(this);
        address resolver = address(0);
        uint64 duration = REGISTRATION_DURATION;
        bytes32 secret = SECRET;
        
        // Make commitment
        bytes32 commitment = registrar.makeCommitment(
            name, 
            owner, 
            secret, 
            address(registry),
            resolver,
            duration
        );
        registrar.commit(commitment);
        
        // Wait for min commitment age
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        // Record logs to check for events
        vm.recordLogs();
        
        // Register the name
        uint256 tokenId = registrar.register(
            name, 
            owner, 
            secret,
            registry,
            resolver,
            duration,
            address(usdc)
        );
        
        // Verify ownership
        assertEq(registry.ownerOf(tokenId), owner);
        
        // Verify expiry
        uint64 expiry = registry.getExpiry(tokenId);
        assertEq(expiry, uint64(block.timestamp) + duration);
        
        // Check for NameRegistered event using the library
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundEvent =
            EventUtils.checkEvent(entries, keccak256("NameRegistered(string,address,address,address,uint64,uint256,uint256,uint256)"));
        assertTrue(foundEvent, "NameRegistered event not emitted");
    }

    function test_register_sets_all_roles() public {
        string memory name = "testname";
        address owner = address(this);
        address resolver = address(0);
        uint64 duration = REGISTRATION_DURATION;
        bytes32 secret = SECRET;
        
        bytes32 commitment = registrar.makeCommitment(
            name, 
            owner, 
            secret, 
            address(registry),
            resolver,
            duration
        );
        registrar.commit(commitment);
        
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        uint256 tokenId = registrar.register(
            name, 
            owner, 
            secret,
            registry,
            resolver,
            duration,
            address(usdc)
        );

        uint256 resource = registry.testGetResourceFromTokenId(tokenId);
        assertTrue(registry.hasRoles(resource, LibEACBaseRoles.ALL_ROLES, owner));
    }

    function test_Revert_insufficientTokenBalance() public {
        string memory name = "testname";
        address owner = address(this);
        address resolver = address(0);
        uint64 duration = REGISTRATION_DURATION;
        bytes32 secret = SECRET;
        
        // Make commitment
        bytes32 commitment = registrar.makeCommitment(
            name, 
            owner, 
            secret, 
            address(registry),
            resolver,
            duration
        );
        registrar.commit(commitment);
        
        // Wait for min commitment age
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        // Calculate the exact token amount needed for this registration
        uint256 exactAmountNeeded = registrar.checkPrice(name, duration, address(usdc));
        
        // Reset approval to 0 to simulate insufficient balance/approval
        usdc.approve(address(registrar), 0);
        
        // Try to register with insufficient token approval - should revert with exact error
        vm.expectRevert(abi.encodeWithSelector(
            bytes4(keccak256("ERC20InsufficientAllowance(address,uint256,uint256)")),
            address(registrar), // spender
            0,                  // current allowance
            exactAmountNeeded   // needed amount
        ));
        registrar.register(
            name, 
            owner, 
            secret,
            registry,
            resolver,
            duration,
            address(usdc)
        );
    }

    function test_Revert_commitmentTooNew() public {
        string memory name = "testname";
        address owner = address(this);
        address resolver = address(0);
        uint64 duration = REGISTRATION_DURATION;
        bytes32 secret = SECRET;
        
        // Make commitment
        bytes32 commitment = registrar.makeCommitment(
            name, 
            owner, 
            secret, 
            address(registry),
            resolver,
            duration
        );
        registrar.commit(commitment);
        
        // Try to register immediately (commitment too new)
        bytes32 expectedCommitment = registrar.makeCommitment(
            name, 
            owner, 
            secret, 
            address(registry),
            resolver,
            duration
        );
        vm.expectRevert(abi.encodeWithSelector(ETHRegistrar.CommitmentTooNew.selector, expectedCommitment, block.timestamp + MIN_COMMITMENT_AGE, block.timestamp));
        registrar.register(
            name, 
            owner, 
            secret,
            registry,
            resolver,
            duration,
            address(usdc)
        );
    }

    function test_Revert_commitmentTooOld() public {
        string memory name = "testname";
        address owner = address(this);
        address resolver = address(0);
        uint64 duration = REGISTRATION_DURATION;
        bytes32 secret = SECRET;
        
        // Make commitment
        bytes32 commitment = registrar.makeCommitment(
            name, 
            owner, 
            secret, 
            address(registry),
            resolver,
            duration
        );
        registrar.commit(commitment);
        
        // Wait for max commitment age
        vm.warp(block.timestamp + MAX_COMMITMENT_AGE + 1);
        
        // Try to register after commitment expired
        bytes32 expectedCommitment = registrar.makeCommitment(
            name, 
            owner, 
            secret, 
            address(registry),
            resolver,
            duration
        );
        vm.expectRevert(abi.encodeWithSelector(ETHRegistrar.CommitmentTooOld.selector, expectedCommitment, block.timestamp - 1, block.timestamp));
        registrar.register(
            name, 
            owner, 
            secret,
            registry,
            resolver,
            duration,
            address(usdc)
        );
    }

    function test_Revert_nameNotAvailable() public {
        string memory name = "testname";
        address owner = address(this);
        address resolver = address(0);
        uint64 duration = REGISTRATION_DURATION;
        bytes32 secret = SECRET;
        
        // Register the name first
        bytes32 commitment = registrar.makeCommitment(
            name, 
            owner, 
            secret, 
            address(registry),
            resolver,
            duration
        );
        registrar.commit(commitment);
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        registrar.register(
            name, 
            owner, 
            secret,
            registry,
            resolver,
            duration,
            address(usdc)
        );
        
        // Try to register again with user1
        vm.startPrank(user1);
        bytes32 secret2 = bytes32(uint256(2345678901));
        
        // Make a commitment
        bytes32 commitment2 = registrar.makeCommitment(
            name, 
            user1, 
            secret2, 
            address(registry),
            resolver,
            duration
        );
        registrar.commit(commitment2);
        
        // Wait for min commitment age to ensure the commitment is valid
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        // This should now fail with NameNotAvailable
        vm.expectRevert(abi.encodeWithSelector(ETHRegistrar.NameNotAvailable.selector, name));
        registrar.register(
            name, 
            user1, 
            secret2,
            registry,
            resolver,
            duration,
            address(usdc)
        );
        vm.stopPrank();
    }

    function test_Revert_durationTooShort() public {
        string memory name = "testname";
        address owner = address(this);
        address resolver = address(0);
        uint64 duration = 1 days; // Too short
        bytes32 secret = SECRET;
        
        // Make commitment
        bytes32 commitment = registrar.makeCommitment(
            name, 
            owner, 
            secret, 
            address(registry),
            resolver,
            duration
        );
        registrar.commit(commitment);
        
        // Wait for min commitment age
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        // Try to register with duration too short
        vm.expectRevert(abi.encodeWithSelector(ETHRegistrar.DurationTooShort.selector, duration, 28 days));
        registrar.register(
            name, 
            owner, 
            secret,
            registry,
            resolver,
            duration,
            address(usdc)
        );
    }

    function test_Revert_invalidOwner() public {
        string memory name = "testname";
        address owner = address(0); // Invalid owner - zero address
        address resolver = address(0);
        uint64 duration = REGISTRATION_DURATION;
        bytes32 secret = SECRET;
        
        // Make commitment
        bytes32 commitment = registrar.makeCommitment(
            name, 
            owner, 
            secret, 
            address(registry),
            resolver,
            duration
        );
        registrar.commit(commitment);
        
        // Wait for min commitment age
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        // Try to register with invalid owner (address(0))
        vm.expectRevert(abi.encodeWithSelector(ETHRegistrar.InvalidOwner.selector, owner));
        registrar.register(
            name, 
            owner, 
            secret,
            registry,
            resolver,
            duration,
            address(usdc)
        );
    }

    function test_renew() public {
        string memory name = "testname";
        address owner = address(this);
        address resolver = address(0);
        uint64 duration = REGISTRATION_DURATION;
        bytes32 secret = SECRET;
        
        // Register the name first
        bytes32 commitment = registrar.makeCommitment(
            name, 
            owner, 
            secret, 
            address(registry),
            resolver,
            duration
        );
        registrar.commit(commitment);
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        uint256 tokenId = registrar.register(
            name, 
            owner, 
            secret,
            registry,
            resolver,
            duration,
            address(usdc)
        );
        
        // Get initial expiry
        uint64 initialExpiry = registry.getExpiry(tokenId);
        
        // Renew the name
        uint64 renewalDuration = 180 days;
        
        // Record logs to check for events
        vm.recordLogs();
        
        registrar.renew(name, renewalDuration, address(usdc));
        
        // Verify new expiry
        uint64 newExpiry = registry.getExpiry(tokenId);
        assertEq(newExpiry, initialExpiry + renewalDuration);
        
        // Check for NameRenewed event using the library
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundEvent = EventUtils.checkEvent(entries, keccak256("NameRenewed(string,uint64,uint256,uint64,uint256)"));
        assertTrue(foundEvent, "NameRenewed event not emitted");
    }

    function test_Revert_renewInsufficientTokenBalance() public {
        string memory name = "testname";
        address owner = address(this);
        address resolver = address(0);
        uint64 duration = REGISTRATION_DURATION;
        bytes32 secret = SECRET;
        
        // Register the name first
        bytes32 commitment = registrar.makeCommitment(
            name, 
            owner, 
            secret, 
            address(registry),
            resolver,
            duration
        );
        registrar.commit(commitment);
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        registrar.register(
            name, 
            owner, 
            secret,
            registry,
            resolver,
            duration,
            address(usdc)
        );
        
        // Calculate the exact token amount needed for renewal
        uint64 renewalDuration = 180 days;
        uint256 exactAmountNeeded = registrar.checkPrice(name, renewalDuration, address(usdc));
        
        // Reset approval to 0 to simulate insufficient balance/approval
        usdc.approve(address(registrar), 0);
        
        // Try to renew with insufficient token approval - should revert with exact error
        vm.expectRevert(abi.encodeWithSelector(
            bytes4(keccak256("ERC20InsufficientAllowance(address,uint256,uint256)")),
            address(registrar), // spender
            0,                  // current allowance
            exactAmountNeeded   // needed amount
        ));
        registrar.renew(name, renewalDuration, address(usdc));
    }

    function test_beneficiary_address_set() public view {
        assertEq(registrar.beneficiary(), beneficiary, "Beneficiary address not set correctly");
    }

    function test_supportsInterface() public view {
        // Use type(IETHRegistrar).interfaceId directly
        bytes4 ethRegistrarInterfaceId = type(IETHRegistrar).interfaceId;
        bytes4 eacInterfaceId = type(IEnhancedAccessControl).interfaceId;
        
        assertTrue(registrar.supportsInterface(ethRegistrarInterfaceId));
        assertTrue(registrar.supportsInterface(eacInterfaceId));
    }

    function test_token_payment_no_refund() public {
        string memory name = "testname";
        address owner = address(this);
        address resolver = address(0);
        uint64 duration = REGISTRATION_DURATION;
        bytes32 secret = SECRET;
        
        // Make commitment
        bytes32 commitment = registrar.makeCommitment(
            name, 
            owner, 
            secret, 
            address(registry),
            resolver,
            duration
        );
        registrar.commit(commitment);
        
        // Wait for min commitment age
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        // Get initial balance
        uint256 initialBalance = address(this).balance;
        
        // Register with exact payment (tokens don't have excess payment)
        registrar.register(
            name, 
            owner, 
            secret,
            registry,
            resolver,
            duration,
            address(usdc)
        );
        
        // Verify no ETH charge (tokens used instead)
        assertEq(address(this).balance, initialBalance);
    }

    function test_registration_forwards_payment_to_beneficiary() public {
        string memory name = "testname";
        address owner = address(this);
        address resolver = address(0);
        uint64 duration = REGISTRATION_DURATION;
        bytes32 secret = SECRET;

        // Check initial balances
        uint256 initialBeneficiaryBalance = usdc.balanceOf(beneficiary);
        uint256 expectedCost = PRICE_5_CHAR * duration;

        // Make commitment
        bytes32 commitment = registrar.makeCommitment(name, owner, secret, address(registry), resolver, duration);
        registrar.commit(commitment);

        // Wait for min commitment age
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);

        // Register the name
        registrar.register(name, owner, secret, registry, resolver, duration, address(usdc));

        // Verify payment was forwarded to beneficiary
        uint256 finalBeneficiaryBalance = usdc.balanceOf(beneficiary);
        assertEq(finalBeneficiaryBalance, initialBeneficiaryBalance + expectedCost, "Payment not forwarded to beneficiary");
    }

    function test_renewal_forwards_payment_to_beneficiary() public {
        string memory name = "testname";
        address owner = address(this);
        address resolver = address(0);
        uint64 duration = REGISTRATION_DURATION;
        bytes32 secret = SECRET;

        // Register the name first
        bytes32 commitment = registrar.makeCommitment(name, owner, secret, address(registry), resolver, duration);
        registrar.commit(commitment);
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        registrar.register(name, owner, secret, registry, resolver, duration, address(usdc));

        // Check beneficiary balance before renewal
        uint256 initialBeneficiaryBalance = usdc.balanceOf(beneficiary);
        uint64 renewalDuration = 180 days;
        uint256 expectedRenewalCost = registrar.checkPrice(name, renewalDuration, address(usdc));

        // Renew the name
        registrar.renew(name, renewalDuration, address(usdc));

        // Verify renewal payment was forwarded to beneficiary
        uint256 finalBeneficiaryBalance = usdc.balanceOf(beneficiary);
        assertEq(finalBeneficiaryBalance, initialBeneficiaryBalance + expectedRenewalCost, "Renewal payment not forwarded to beneficiary");
    }

    function test_token_payment_renew_no_refund() public {
        string memory name = "testname";
        address owner = address(this);
        address resolver = address(0);
        uint64 duration = REGISTRATION_DURATION;
        bytes32 secret = SECRET;
        
        // Register the name first
        bytes32 commitment = registrar.makeCommitment(
            name, 
            owner, 
            secret, 
            address(registry),
            resolver,
            duration
        );
        registrar.commit(commitment);
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        registrar.register(
            name, 
            owner, 
            secret,
            registry,
            resolver,
            duration,
            address(usdc)
        );
        
        // Get initial balance
        uint256 initialBalance = address(this).balance;
        
        // Renew with exact payment (tokens don't have excess payment)
        uint64 renewalDuration = 180 days;
        
        registrar.renew(name, renewalDuration, address(usdc));
        
        // Verify no ETH charge (tokens used instead)
        assertEq(address(this).balance, initialBalance);
    }

    function test_registration_default_role_bitmap() public {
        bytes32 commitment = registrar.makeCommitment(
            "testname", 
            user1, 
            SECRET, 
            address(registry),
            address(0),
            REGISTRATION_DURATION
        );
        registrar.commit(commitment);
        
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        uint256 tokenId = registrar.register(
            "testname", 
            user1, 
            SECRET,
            registry,
            address(0),
            REGISTRATION_DURATION,
            address(usdc)
        );

        uint256 resource = registry.testGetResourceFromTokenId(tokenId);

        // Check individual roles
        uint256 ROLE_SET_SUBREGISTRY = 1 << 8;
        uint256 ROLE_SET_SUBREGISTRY_ADMIN = ROLE_SET_SUBREGISTRY << 128;
        uint256 ROLE_SET_RESOLVER = 1 << 12;
        uint256 ROLE_SET_RESOLVER_ADMIN = ROLE_SET_RESOLVER << 128;

        assertTrue(registry.hasRoles(resource, ROLE_SET_SUBREGISTRY, user1));
        assertTrue(registry.hasRoles(resource, ROLE_SET_SUBREGISTRY_ADMIN, user1));
        assertTrue(registry.hasRoles(resource, ROLE_SET_RESOLVER, user1));
        assertTrue(registry.hasRoles(resource, ROLE_SET_RESOLVER_ADMIN, user1));

        // Check combined bitmap
        uint256 ROLE_BITMAP_REGISTRATION = ROLE_SET_SUBREGISTRY | ROLE_SET_SUBREGISTRY_ADMIN | ROLE_SET_RESOLVER | ROLE_SET_RESOLVER_ADMIN;
        assertTrue(registry.hasRoles(resource, ROLE_BITMAP_REGISTRATION, user1));
    }

    function test_length_based_pricing_integration() public view {
        // Test different name lengths get different prices
        uint64 duration = 365 days;
        
        // 3 character name: 4 attousd/sec
        uint256 price3 = registrar.checkPrice("eth", duration, address(usdc));
        assertEq(price3, PRICE_3_CHAR * duration);
        
        // 4 character name: 2 attousd/sec  
        uint256 price4 = registrar.checkPrice("test", duration, address(usdc));
        assertEq(price4, PRICE_4_CHAR * duration);
        
        // 5+ character name: 1 attousd/sec
        uint256 price5 = registrar.checkPrice("alice", duration, address(usdc));
        assertEq(price5, PRICE_5_CHAR * duration);
        
        // Very long name should use same as 5+ chars
        uint256 priceLong = registrar.checkPrice("verylongname", duration, address(usdc));
        assertEq(priceLong, PRICE_5_CHAR * duration);
    }

    function test_unsupported_name_lengths_pricing() public view {
        uint64 duration = 365 days;
        
        // 1 and 2 character names should return 0 price (not supported)
        uint256 price1 = registrar.checkPrice("a", duration, address(usdc));
        assertEq(price1, 0);
        
        uint256 price2 = registrar.checkPrice("ab", duration, address(usdc));
        assertEq(price2, 0);
    }

    // Test that valid() function is enforced during registration
    function test_cannot_register_short_names() public {
        // Test that 1-char names are rejected
        vm.expectRevert(abi.encodeWithSelector(ETHRegistrar.NameNotAvailable.selector, "a"));
        registrar.register(
            "a",
            user1,
            SECRET,
            IRegistry(address(0)),
            address(0),
            REGISTRATION_DURATION,
            address(usdc)
        );
        
        // Test that 2-char names are rejected
        vm.expectRevert(abi.encodeWithSelector(ETHRegistrar.NameNotAvailable.selector, "ab"));
        registrar.register(
            "ab",
            user1,
            SECRET,
            IRegistry(address(0)),
            address(0),
            REGISTRATION_DURATION,
            address(usdc)
        );
    }

    receive() external payable {}
} 


library EventUtils {
    function checkEvent(
        Vm.Log[] memory logs,
        bytes32 eventSignature
    ) internal pure returns (bool) {
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                return true;
            }
        }
        
        return false;
    }
}