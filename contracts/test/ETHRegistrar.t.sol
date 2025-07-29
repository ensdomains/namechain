// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "../src/L2/ETHRegistrar.sol";
import "./mocks/MockPermissionedRegistry.sol";
import "../src/common/RegistryDatastore.sol";
import {IPriceOracle} from "@ens/contracts/ethregistrar/IPriceOracle.sol";
import "../src/common/SimpleRegistryMetadata.sol";
import "../src/common/EnhancedAccessControl.sol";
import "../src/common/IEnhancedAccessControl.sol";
import "../src/common/NameUtils.sol";
import {Vm} from "forge-std/Vm.sol";
import {LibEACBaseRoles} from "../src/common/EnhancedAccessControl.sol";
import {LibRegistryRoles} from "../src/common/LibRegistryRoles.sol";

contract MockPriceOracle is IPriceOracle {
    uint256 public basePrice;
    uint256 public premiumPrice;

    constructor(uint256 _basePrice, uint256 _premiumPrice) {
        basePrice = _basePrice;
        premiumPrice = _premiumPrice;
    }

    function price(
        string calldata /*name*/,
        uint256 /*expires*/,
        uint256 /*duration*/
    ) external view returns (Price memory) {
        return Price(basePrice, premiumPrice);
    }
}

contract TestETHRegistrar is Test, ERC1155Holder {
    RegistryDatastore datastore;
    MockPermissionedRegistry registry;
    ETHRegistrar registrar;
    MockPriceOracle priceOracle;

    address user1 = address(0x1);
    address user2 = address(0x2);
    
    uint256 constant MIN_COMMITMENT_AGE = 60; // 1 minute
    uint256 constant MAX_COMMITMENT_AGE = 86400; // 1 day
    uint256 constant BASE_PRICE = 0.01 ether;
    uint256 constant PREMIUM_PRICE = 0.005 ether;
    uint64 constant REGISTRATION_DURATION = 365 days;
    bytes32 constant SECRET = bytes32(uint256(1234567890));

    // Hardcoded role constants

    
    uint256 constant ROLE_SET_PRICE_ORACLE = 1 << 20;
    uint256 constant ROLE_SET_PRICE_ORACLE_ADMIN = ROLE_SET_PRICE_ORACLE << 128;
    uint256 constant ROLE_SET_COMMITMENT_AGES = 1 << 24;
    uint256 constant ROLE_SET_COMMITMENT_AGES_ADMIN = ROLE_SET_COMMITMENT_AGES << 128;
    
    uint256 constant ROOT_RESOURCE = 0;

    function setUp() public {
        // Set the timestamp to a future date to avoid timestamp related issues
        vm.warp(2_000_000_000);

        datastore = new RegistryDatastore();
        // Use a defined ALL_ROLES value for deployer roles
        uint256 deployerRoles = LibEACBaseRoles.ALL_ROLES;
        registry = new MockPermissionedRegistry(datastore, new SimpleRegistryMetadata(), address(this), deployerRoles);
        priceOracle = new MockPriceOracle(BASE_PRICE, PREMIUM_PRICE);
        
        registrar = new ETHRegistrar(address(registry), priceOracle, MIN_COMMITMENT_AGE, MAX_COMMITMENT_AGE);
        
        registry.grantRootRoles(LibRegistryRoles.ROLE_REGISTRAR | LibRegistryRoles.ROLE_RENEW, address(registrar));
        
        vm.deal(address(this), 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
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
        new ETHRegistrar(address(registry), priceOracle, invalidMinAge, invalidMaxAge);
        
        // Try with max age less than min age
        invalidMaxAge = 99; // Less than minAge, should revert
        
        vm.expectRevert(abi.encodeWithSelector(ETHRegistrar.MaxCommitmentAgeTooLow.selector));
        new ETHRegistrar(address(registry), priceOracle, invalidMinAge, invalidMaxAge);
    }

    function test_available() public {
        string memory name = "testname";
        assertTrue(registrar.available(name));
        
        // Register the name
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
        
        registrar.register{value: BASE_PRICE + PREMIUM_PRICE}(
            name, 
            address(this), 
            SECRET,
            registry,
            address(0), // resolver
            REGISTRATION_DURATION
        );
        
        // Now the name should not be available
        assertFalse(registrar.available(name));
    }

    function test_rentPrice() public view {
        string memory name = "testname";
        IPriceOracle.Price memory price = registrar.rentPrice(name, REGISTRATION_DURATION);
        
        assertEq(price.base, BASE_PRICE);
        assertEq(price.premium, PREMIUM_PRICE);
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
        uint256 tokenId = registrar.register{value: BASE_PRICE + PREMIUM_PRICE}(
            name, 
            owner, 
            secret,
            registry,
            resolver,
            duration
        );
        
        // Verify ownership
        assertEq(registry.ownerOf(tokenId), owner);
        
        // Verify expiry
        uint64 expiry = registry.getExpiry(tokenId);
        assertEq(expiry, uint64(block.timestamp) + duration);
        
        // Check for NameRegistered event using the library
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundEvent = EventUtils.checkEvent(
            entries,
            keccak256("NameRegistered(string,address,address,address,uint64,uint256)")
        );
        
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
        
        uint256 tokenId = registrar.register{value: BASE_PRICE + PREMIUM_PRICE}(
            name, 
            owner, 
            secret,
            registry,
            resolver,
            duration
        );

        uint256 resource = registry.testGetTokenIdResource(tokenId);
        assertTrue(registry.hasRoles(resource, LibEACBaseRoles.ALL_ROLES, owner));
    }

    function test_Revert_insufficientValue() public {
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
        
        // Try to register with insufficient value
        uint256 totalPrice = BASE_PRICE + PREMIUM_PRICE;
        vm.expectRevert(abi.encodeWithSelector(ETHRegistrar.InsufficientValue.selector, totalPrice, BASE_PRICE));
        registrar.register{value: BASE_PRICE}(
            name, 
            owner, 
            secret,
            registry,
            resolver,
            duration
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
        registrar.register{value: BASE_PRICE + PREMIUM_PRICE}(
            name, 
            owner, 
            secret,
            registry,
            resolver,
            duration
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
        registrar.register{value: BASE_PRICE + PREMIUM_PRICE}(
            name, 
            owner, 
            secret,
            registry,
            resolver,
            duration
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
        registrar.register{value: BASE_PRICE + PREMIUM_PRICE}(
            name, 
            owner, 
            secret,
            registry,
            resolver,
            duration
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
        registrar.register{value: BASE_PRICE + PREMIUM_PRICE}(
            name, 
            user1, 
            secret2,
            registry,
            resolver,
            duration
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
        registrar.register{value: BASE_PRICE + PREMIUM_PRICE}(
            name, 
            owner, 
            secret,
            registry,
            resolver,
            duration
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
        uint256 tokenId = registrar.register{value: BASE_PRICE + PREMIUM_PRICE}(
            name, 
            owner, 
            secret,
            registry,
            resolver,
            duration
        );
        
        // Get initial expiry
        uint64 initialExpiry = registry.getExpiry(tokenId);
        
        // Renew the name
        uint64 renewalDuration = 180 days;
        
        // Record logs to check for events
        vm.recordLogs();
        
        registrar.renew{value: BASE_PRICE + PREMIUM_PRICE}(name, renewalDuration);
        
        // Verify new expiry
        uint64 newExpiry = registry.getExpiry(tokenId);
        assertEq(newExpiry, initialExpiry + renewalDuration);
        
        // Check for NameRenewed event using the library
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundEvent = EventUtils.checkEvent(
            entries,
            keccak256("NameRenewed(string,uint64,uint256,uint64)")
        );
        
        assertTrue(foundEvent, "NameRenewed event not emitted");
    }

    function test_Revert_renewInsufficientValue() public {
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
        registrar.register{value: BASE_PRICE + PREMIUM_PRICE}(
            name, 
            owner, 
            secret,
            registry,
            resolver,
            duration
        );
        
        // Try to renew with insufficient value
        uint64 renewalDuration = 180 days;
        uint256 totalPrice = BASE_PRICE + PREMIUM_PRICE;
        vm.expectRevert(abi.encodeWithSelector(ETHRegistrar.InsufficientValue.selector, totalPrice, BASE_PRICE));
        registrar.renew{value: BASE_PRICE}(name, renewalDuration);
    }

    function test_supportsInterface() public view {
        // Use type(IETHRegistrar).interfaceId directly
        bytes4 ethRegistrarInterfaceId = type(IETHRegistrar).interfaceId;
        bytes4 eacInterfaceId = type(IEnhancedAccessControl).interfaceId;
        
        assertTrue(registrar.supportsInterface(ethRegistrarInterfaceId));
        assertTrue(registrar.supportsInterface(eacInterfaceId));
    }

    function test_refund_excess_payment() public {
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
        
        // Register with excess payment
        uint256 excessAmount = 0.5 ether;
        registrar.register{value: BASE_PRICE + PREMIUM_PRICE + excessAmount}(
            name, 
            owner, 
            secret,
            registry,
            resolver,
            duration
        );
        
        // Verify refund
        assertEq(address(this).balance, initialBalance - (BASE_PRICE + PREMIUM_PRICE));
    }

    function test_refund_excess_payment_renew() public {
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
        registrar.register{value: BASE_PRICE + PREMIUM_PRICE}(
            name, 
            owner, 
            secret,
            registry,
            resolver,
            duration
        );
        
        // Get initial balance
        uint256 initialBalance = address(this).balance;
        
        // Renew with excess payment
        uint256 excessAmount = 0.5 ether;
        uint64 renewalDuration = 180 days;
        
        registrar.renew{value: BASE_PRICE + PREMIUM_PRICE + excessAmount}(name, renewalDuration);
        
        // Verify refund
        assertEq(address(this).balance, initialBalance - (BASE_PRICE + PREMIUM_PRICE));
    }

    function test_setPriceOracle() public {
        MockPriceOracle newPriceOracle = new MockPriceOracle(0.02 ether, 0.01 ether);
        registrar.setPriceOracle(newPriceOracle);
        assertEq(address(registrar.prices()), address(newPriceOracle));
    }

    function test_setCommitmentAges() public {
        uint256 newMinAge = 120;
        uint256 newMaxAge = 172800;
        registrar.setCommitmentAges(newMinAge, newMaxAge);
        assertEq(registrar.minCommitmentAge(), newMinAge);
        assertEq(registrar.maxCommitmentAge(), newMaxAge);
    }

    function test_Revert_setCommitmentAges_maxTooLow() public {
        uint256 newMinAge = 120;
        uint256 newMaxAge = 119;
        vm.expectRevert(abi.encodeWithSelector(ETHRegistrar.MaxCommitmentAgeTooLow.selector));
        registrar.setCommitmentAges(newMinAge, newMaxAge);
    }

    function test_Revert_setPriceOracle_notAdmin() public {
        vm.startPrank(user1);
        MockPriceOracle newPriceOracle = new MockPriceOracle(0.02 ether, 0.01 ether);
        vm.expectRevert(abi.encodeWithSelector(IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector, ROOT_RESOURCE, ROLE_SET_PRICE_ORACLE, user1));
        registrar.setPriceOracle(newPriceOracle);
        vm.stopPrank();
    }

    function test_Revert_setCommitmentAges_notAdmin() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector, ROOT_RESOURCE, ROLE_SET_COMMITMENT_AGES, user1));
        registrar.setCommitmentAges(120, 172800);
        vm.stopPrank();
    }

    function test_roleGranting_priceOracle() public {
        // Grant the price oracle role to user1
        vm.startPrank(address(this));
        registrar.grantRootRoles(ROLE_SET_PRICE_ORACLE, user1);
        vm.stopPrank();
        
        // Check that user1 can now set the price oracle
        vm.startPrank(user1);
        MockPriceOracle newPriceOracle = new MockPriceOracle(0.02 ether, 0.01 ether);
        registrar.setPriceOracle(newPriceOracle);
        assertEq(address(registrar.prices()), address(newPriceOracle));
        vm.stopPrank();
    }

    function test_roleGranting_commitmentAges() public {
        // Grant the commitment ages role to user1
        vm.startPrank(address(this));
        registrar.grantRootRoles(ROLE_SET_COMMITMENT_AGES, user1);
        vm.stopPrank();
        
        // Check that user1 can now set the commitment ages
        vm.startPrank(user1);
        uint256 newMinAge = 150;
        uint256 newMaxAge = 200000;
        registrar.setCommitmentAges(newMinAge, newMaxAge);
        assertEq(registrar.minCommitmentAge(), newMinAge);
        assertEq(registrar.maxCommitmentAge(), newMaxAge);
        vm.stopPrank();
    }

    function test_roleAdminFunctionality_priceOracle() public {
        // Grant the price oracle admin role to user1
        vm.startPrank(address(this));
        registrar.grantRootRoles(ROLE_SET_PRICE_ORACLE_ADMIN, user1);
        vm.stopPrank();
        
        // User1 can now grant the price oracle role to user2
        vm.startPrank(user1);
        registrar.grantRootRoles(ROLE_SET_PRICE_ORACLE, user2);
        vm.stopPrank();
        
        // Check that user2 can now set the price oracle
        vm.startPrank(user2);
        MockPriceOracle newPriceOracle = new MockPriceOracle(0.03 ether, 0.015 ether);
        registrar.setPriceOracle(newPriceOracle);
        assertEq(address(registrar.prices()), address(newPriceOracle));
        vm.stopPrank();
    }

    function test_roleAdminFunctionality_commitmentAges() public {
        // Grant the commitment ages admin role to user1
        vm.startPrank(address(this));
        registrar.grantRootRoles(ROLE_SET_COMMITMENT_AGES_ADMIN, user1);
        vm.stopPrank();
        
        // User1 can now grant the commitment ages role to user2
        vm.startPrank(user1);
        registrar.grantRootRoles(ROLE_SET_COMMITMENT_AGES, user2);
        vm.stopPrank();
        
        // Check that user2 can now set the commitment ages
        vm.startPrank(user2);
        uint256 newMinAge = 180;
        uint256 newMaxAge = 250000;
        registrar.setCommitmentAges(newMinAge, newMaxAge);
        assertEq(registrar.minCommitmentAge(), newMinAge);
        assertEq(registrar.maxCommitmentAge(), newMaxAge);
        vm.stopPrank();
    }

    function test_roleAdminSeparation_priceOracleAdmin_cannotChangeCommitmentAges() public {
        // First, grant the price oracle admin role to user1 
        vm.startPrank(address(this));
        registrar.grantRootRoles(ROLE_SET_PRICE_ORACLE_ADMIN, user1);
        vm.stopPrank();
        
        // User1 should not be able to set commitment ages
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector, ROOT_RESOURCE, ROLE_SET_COMMITMENT_AGES, user1));
        registrar.setCommitmentAges(120, 172800);
        vm.stopPrank();
    }

    function test_roleAdminSeparation_commitmentAgesAdmin_cannotChangePriceOracle() public {
        // First, grant the commitment ages admin role to user1
        vm.startPrank(address(this));
        registrar.grantRootRoles(ROLE_SET_COMMITMENT_AGES_ADMIN, user1);
        vm.stopPrank();
        
        // User1 should not be able to set price oracle
        vm.startPrank(user1);
        MockPriceOracle newPriceOracle = new MockPriceOracle(0.02 ether, 0.01 ether);
        vm.expectRevert(abi.encodeWithSelector(IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector, ROOT_RESOURCE, ROLE_SET_PRICE_ORACLE, user1));
        registrar.setPriceOracle(newPriceOracle);
        vm.stopPrank();
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
        
        uint256 tokenId = registrar.register{value: BASE_PRICE + PREMIUM_PRICE}(
            "testname", 
            user1, 
            SECRET,
            registry,
            address(0),
            REGISTRATION_DURATION
        );

        uint256 resource = registry.testGetTokenIdResource(tokenId);

        // Check individual roles
        uint256 ROLE_SET_SUBREGISTRY = 1 << 8;
        uint256 ROLE_SET_SUBREGISTRY_ADMIN = ROLE_SET_SUBREGISTRY << 128;
        uint256 ROLE_SET_RESOLVER = 1 << 12;
        uint256 ROLE_SET_RESOLVER_ADMIN = ROLE_SET_RESOLVER << 128;
        uint256 ROLE_SET_TOKEN_OBSERVER = 1 << 16;
        uint256 ROLE_SET_TOKEN_OBSERVER_ADMIN = ROLE_SET_TOKEN_OBSERVER << 128;

        assertTrue(registry.hasRoles(resource, ROLE_SET_SUBREGISTRY, user1));
        assertTrue(registry.hasRoles(resource, ROLE_SET_SUBREGISTRY_ADMIN, user1));
        assertTrue(registry.hasRoles(resource, ROLE_SET_RESOLVER, user1));
        assertTrue(registry.hasRoles(resource, ROLE_SET_RESOLVER_ADMIN, user1));
        assertTrue(registry.hasRoles(resource, ROLE_SET_TOKEN_OBSERVER, user1));
        assertTrue(registry.hasRoles(resource, ROLE_SET_TOKEN_OBSERVER_ADMIN, user1));

        // Check combined bitmap
        uint256 ROLE_BITMAP_REGISTRATION = ROLE_SET_SUBREGISTRY | ROLE_SET_SUBREGISTRY_ADMIN | ROLE_SET_RESOLVER | ROLE_SET_RESOLVER_ADMIN | ROLE_SET_TOKEN_OBSERVER | ROLE_SET_TOKEN_OBSERVER_ADMIN;
        assertTrue(registry.hasRoles(resource, ROLE_BITMAP_REGISTRATION, user1));
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