// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "../src/registry/ETHRegistrar.sol";
import "../src/registry/ETHRegistry.sol";
import "../src/registry/RegistryDatastore.sol";
import "../src/registry/IPriceOracle.sol";
import "../src/utils/NameUtils.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Vm} from "forge-std/Vm.sol";


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
    ETHRegistry registry;
    ETHRegistrar registrar;
    MockPriceOracle priceOracle;

    address user1 = address(0x1);
    address user2 = address(0x2);
    
    uint256 constant MIN_COMMITMENT_AGE = 60; // 1 minute
    uint256 constant MAX_COMMITMENT_AGE = 86400; // 1 day
    uint256 constant BASE_PRICE = 0.01 ether;
    uint256 constant PREMIUM_PRICE = 0.005 ether;
    uint64 constant REGISTRATION_DURATION = 365 days;

    function setUp() public {
        // Set the timestamp to a future date to avoid timestamp related issues
        vm.warp(2_000_000_000);

        datastore = new RegistryDatastore();
        registry = new ETHRegistry(datastore);
        priceOracle = new MockPriceOracle(BASE_PRICE, PREMIUM_PRICE);
        
        registrar = new ETHRegistrar(address(registry), priceOracle, MIN_COMMITMENT_AGE, MAX_COMMITMENT_AGE);
        
        registry.grantRole(registry.REGISTRAR_ROLE(), address(registrar));
        registrar.grantRole(registrar.CONTROLLER_ROLE(), address(this));
        
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

    function test_available() public {
        string memory name = "testname";
        assertTrue(registrar.available(name));
        
        // Register the name
        bytes32 commitment = registrar.makeCommitment(
            name, 
            address(this), 
            bytes32(0), 
            address(registry), 
            0, 
            REGISTRATION_DURATION
        );
        registrar.commit(commitment);
        
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        registrar.register{value: BASE_PRICE + PREMIUM_PRICE}(
            name, 
            address(this), 
            registry, 
            0, 
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
        uint96 flags = 0;
        uint64 duration = REGISTRATION_DURATION;
        
        bytes32 commitment = registrar.makeCommitment(name, owner, secret, subregistry, flags, duration);
        
        bytes32 expectedCommitment = keccak256(
            abi.encode(
                name,
                owner,
                secret,
                subregistry,
                flags,
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
            0, 
            REGISTRATION_DURATION
        );
        
        registrar.commit(commitment);
        
        // Check that the commitment was stored
        assertEq(registrar.commitments(commitment), block.timestamp);
    }

    function test_Revert_unexpiredCommitment() public {
        string memory name = "testname";
        bytes32 commitment = registrar.makeCommitment(
            name, 
            address(this), 
            bytes32(0), 
            address(registry), 
            0, 
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
        uint96 flags = 0;
        uint64 duration = REGISTRATION_DURATION;
        
        // Make commitment
        bytes32 commitment = registrar.makeCommitment(
            name, 
            owner, 
            bytes32(0), 
            address(registry), 
            flags, 
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
            registry, 
            flags, 
            duration
        );
        
        // Verify ownership
        assertEq(registry.ownerOf(tokenId), owner);
        
        // Verify expiry
        (uint64 expiry, ) = registry.nameData(tokenId);
        assertEq(expiry, uint64(block.timestamp) + duration);
        
        // Check for NameRegistered event using the library
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundEvent = EventUtils.checkEvent(
            entries,
            keccak256("NameRegistered(string,address,address,uint96,uint64,uint256)")
        );
        
        assertTrue(foundEvent, "NameRegistered event not emitted");
    }

    function test_Revert_insufficientValue() public {
        string memory name = "testname";
        address owner = address(this);
        uint96 flags = 0;
        uint64 duration = REGISTRATION_DURATION;
        
        // Make commitment
        bytes32 commitment = registrar.makeCommitment(
            name, 
            owner, 
            bytes32(0), 
            address(registry), 
            flags, 
            duration
        );
        registrar.commit(commitment);
        
        // Wait for min commitment age
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        // Try to register with insufficient value
        vm.expectRevert(ETHRegistrar.InsufficientValue.selector);
        registrar.register{value: BASE_PRICE}(
            name, 
            owner, 
            registry, 
            flags, 
            duration
        );
    }

    function test_Revert_commitmentTooNew() public {
        string memory name = "testname";
        address owner = address(this);
        uint96 flags = 0;
        uint64 duration = REGISTRATION_DURATION;
        
        // Make commitment
        bytes32 commitment = registrar.makeCommitment(
            name, 
            owner, 
            bytes32(0), 
            address(registry), 
            flags, 
            duration
        );
        registrar.commit(commitment);
        
        // Try to register immediately (commitment too new)
        bytes32 expectedCommitment = registrar.makeCommitment(
            name, 
            owner, 
            bytes32(0), 
            address(registry), 
            flags, 
            duration
        );
        vm.expectRevert(abi.encodeWithSelector(ETHRegistrar.CommitmentTooNew.selector, expectedCommitment));
        registrar.register{value: BASE_PRICE + PREMIUM_PRICE}(
            name, 
            owner, 
            registry, 
            flags, 
            duration
        );
    }

    function test_Revert_commitmentTooOld() public {
        string memory name = "testname";
        address owner = address(this);
        uint96 flags = 0;
        uint64 duration = REGISTRATION_DURATION;
        
        // Make commitment
        bytes32 commitment = registrar.makeCommitment(
            name, 
            owner, 
            bytes32(0), 
            address(registry), 
            flags, 
            duration
        );
        registrar.commit(commitment);
        
        // Wait for max commitment age
        vm.warp(block.timestamp + MAX_COMMITMENT_AGE + 1);
        
        // Try to register after commitment expired
        bytes32 expectedCommitment = registrar.makeCommitment(
            name, 
            owner, 
            bytes32(0), 
            address(registry), 
            flags, 
            duration
        );
        vm.expectRevert(abi.encodeWithSelector(ETHRegistrar.CommitmentTooOld.selector, expectedCommitment));
        registrar.register{value: BASE_PRICE + PREMIUM_PRICE}(
            name, 
            owner, 
            registry, 
            flags, 
            duration
        );
    }

    function test_Revert_nameNotAvailable() public {
        string memory name = "testname";
        address owner = address(this);
        uint96 flags = 0;
        uint64 duration = REGISTRATION_DURATION;
        
        // Register the name first
        bytes32 commitment = registrar.makeCommitment(
            name, 
            owner, 
            bytes32(0), 
            address(registry), 
            flags, 
            duration
        );
        registrar.commit(commitment);
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        registrar.register{value: BASE_PRICE + PREMIUM_PRICE}(
            name, 
            owner, 
            registry, 
            flags, 
            duration
        );
        
        // Try to register again with user1
        vm.startPrank(user1);
        
        // First grant CONTROLLER_ROLE to user1
        vm.stopPrank();
        registrar.grantRole(registrar.CONTROLLER_ROLE(), user1);
        vm.startPrank(user1);
        
        bytes32 commitment2 = registrar.makeCommitment(
            name, 
            user1, 
            bytes32(0), 
            address(registry), 
            flags, 
            duration
        );
        registrar.commit(commitment2);
        
        // Wait for min commitment age
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        vm.expectRevert(abi.encodeWithSelector(ETHRegistrar.NameNotAvailable.selector, name));
        registrar.register{value: BASE_PRICE + PREMIUM_PRICE}(
            name, 
            user1, 
            registry, 
            flags, 
            duration
        );
        vm.stopPrank();
    }

    function test_Revert_durationTooShort() public {
        string memory name = "testname";
        address owner = address(this);
        uint96 flags = 0;
        uint64 duration = 1 days; // Too short
        
        // Make commitment
        bytes32 commitment = registrar.makeCommitment(
            name, 
            owner, 
            bytes32(0), 
            address(registry), 
            flags, 
            duration
        );
        registrar.commit(commitment);
        
        // Wait for min commitment age
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        
        // Try to register with duration too short
        vm.expectRevert(abi.encodeWithSelector(ETHRegistrar.DurationTooShort.selector, duration));
        registrar.register{value: BASE_PRICE + PREMIUM_PRICE}(
            name, 
            owner, 
            registry, 
            flags, 
            duration
        );
    }

    function test_renew() public {
        string memory name = "testname";
        address owner = address(this);
        uint96 flags = 0;
        uint64 duration = REGISTRATION_DURATION;
        
        // Register the name first
        bytes32 commitment = registrar.makeCommitment(
            name, 
            owner, 
            bytes32(0), 
            address(registry), 
            flags, 
            duration
        );
        registrar.commit(commitment);
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        uint256 tokenId = registrar.register{value: BASE_PRICE + PREMIUM_PRICE}(
            name, 
            owner, 
            registry, 
            flags, 
            duration
        );
        
        // Get initial expiry
        (uint64 initialExpiry, ) = registry.nameData(tokenId);
        
        // Renew the name
        uint64 renewalDuration = 180 days;
        
        // Record logs to check for events
        vm.recordLogs();
        
        registrar.renew{value: BASE_PRICE + PREMIUM_PRICE}(name, renewalDuration);
        
        // Verify new expiry
        (uint64 newExpiry, ) = registry.nameData(tokenId);
        assertEq(newExpiry, initialExpiry + renewalDuration);
        
        // Check for NameRenewed event using the library
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundEvent = EventUtils.checkEvent(
            entries,
            keccak256("NameRenewed(string,uint64,uint256)")
        );
        
        assertTrue(foundEvent, "NameRenewed event not emitted");
    }

    function test_Revert_renewInsufficientValue() public {
        string memory name = "testname";
        address owner = address(this);
        uint96 flags = 0;
        uint64 duration = REGISTRATION_DURATION;
        
        // Register the name first
        bytes32 commitment = registrar.makeCommitment(
            name, 
            owner, 
            bytes32(0), 
            address(registry), 
            flags, 
            duration
        );
        registrar.commit(commitment);
        vm.warp(block.timestamp + MIN_COMMITMENT_AGE + 1);
        registrar.register{value: BASE_PRICE + PREMIUM_PRICE}(
            name, 
            owner, 
            registry, 
            flags, 
            duration
        );
        
        // Try to renew with insufficient value
        uint64 renewalDuration = 180 days;
        vm.expectRevert(ETHRegistrar.InsufficientValue.selector);
        registrar.renew{value: BASE_PRICE}(name, renewalDuration);
    }

    function test_supportsInterface() public view {
        // Use type(IETHRegistrar).interfaceId directly
        bytes4 ethRegistrarInterfaceId = type(IETHRegistrar).interfaceId;
        bytes4 accessControlInterfaceId = type(IAccessControl).interfaceId;
        
        assertTrue(registrar.supportsInterface(ethRegistrarInterfaceId));
        assertTrue(registrar.supportsInterface(accessControlInterfaceId));
    }

    function test_refund_excess_payment() public {
        string memory name = "testname";
        address owner = address(this);
        uint96 flags = 0;
        uint64 duration = REGISTRATION_DURATION;
        
        // Make commitment
        bytes32 commitment = registrar.makeCommitment(
            name, 
            owner, 
            bytes32(0), 
            address(registry), 
            flags, 
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
            registry, 
            flags, 
            duration
        );
        
        // Verify refund
        assertEq(address(this).balance, initialBalance - (BASE_PRICE + PREMIUM_PRICE));
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
