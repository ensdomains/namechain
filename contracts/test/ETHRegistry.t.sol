// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "../src/common/ETHRegistry.sol";
import "../src/common/RegistryDatastore.sol";
import "../src/common/IRegistryDatastore.sol";
import "../src/common/IRegistryMetadata.sol";
import "../src/common/IEjectionController.sol";
import "../src/common/NameUtils.sol";
import {RegistryRolesMixin} from "../src/common/RegistryRolesMixin.sol";
import {EnhancedAccessControl} from "../src/common/EnhancedAccessControl.sol";

// Mock implementation of the ETHRegistry for testing
contract MockETHRegistry is ETHRegistry {
    constructor(
        IRegistryDatastore _datastore,
        IRegistryMetadata _registryMetadata,
        IEjectionController _ejectionController
    ) ETHRegistry(_datastore, _registryMetadata, _ejectionController) {}
}

// Mock implementation of IRegistryMetadata
contract MockRegistryMetadata is IRegistryMetadata {
    function tokenUri(uint256) external pure override returns (string memory) {
        return "";
    }
}

// Mock implementation of IEjectionController
contract MockEjectionController is IEjectionController {
    // Track calls to onRenew
    bool public renewCalled;
    uint256 public lastRenewedTokenId;
    uint64 public lastRenewedExpires;
    address public lastRenewedBy;

    // Track calls to onRelinquish
    bool public relinquishCalled;
    uint256 public lastRelinquishedTokenId;
    address public lastRelinquishedBy;

    function onRenew(uint256 tokenId, uint64 expires, address renewedBy) external override {
        renewCalled = true;
        lastRenewedTokenId = tokenId;
        lastRenewedExpires = expires;
        lastRenewedBy = renewedBy;
    }

    function onRelinquish(uint256 tokenId, address relinquishedBy) external override {
        relinquishCalled = true;
        lastRelinquishedTokenId = tokenId;
        lastRelinquishedBy = relinquishedBy;
    }
}

contract ETHRegistryTest is Test, ERC1155Holder, RegistryRolesMixin {
    // Constants from EnhancedAccessControl
    bytes32 constant ROOT_RESOURCE = bytes32(0);
    uint256 constant ALL_ROLES = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    
    MockETHRegistry registry;
    RegistryDatastore datastore;
    MockRegistryMetadata registryMetadata;
    MockEjectionController ejectionController;
    MockEjectionController newEjectionController;

    address user = address(0x1);
    
    function setUp() public {
        datastore = new RegistryDatastore();
        registryMetadata = new MockRegistryMetadata();
        ejectionController = new MockEjectionController();
        newEjectionController = new MockEjectionController();
        
        // Deploy the registry with initial ejection controller
        registry = new MockETHRegistry(datastore, registryMetadata, ejectionController);
    }

    function test_constructor_sets_ejection_controller() public view {
        assertEq(address(registry.ejectionController()), address(ejectionController));
    }

    function test_set_ejection_controller() public {
        // Grant this test contract the required role
        registry.grantRootRoles(ROLE_SET_EJECTION_CONTROLLER, address(this));
        
        // Change ejection controller
        vm.recordLogs();
        registry.setEjectionController(newEjectionController);
        
        // Verify the new controller was set
        assertEq(address(registry.ejectionController()), address(newEjectionController));
        
        // Verify event was emitted
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundEvent = false;
        
        for (uint i = 0; i < entries.length; i++) {
            if (entries[i].emitter == address(registry) && 
                entries[i].topics[0] == keccak256("EjectionControllerChanged(address,address)")) {
                
                // The event signature in this contract only has the event name in topics[0]
                // The actual data is in the data field, not in topics[1] and topics[2]
                (address oldController, address newController) = abi.decode(entries[i].data, (address, address));
                
                assertEq(oldController, address(ejectionController));
                assertEq(newController, address(newEjectionController));
                foundEvent = true;
                break;
            }
        }
        
        assertTrue(foundEvent, "EjectionControllerChanged event not found");
    }
    
    function test_set_ejection_controller_reverts_for_zero_address() public {
        // Grant this test contract the required role
        registry.grantRootRoles(ROLE_SET_EJECTION_CONTROLLER, address(this));
        
        // Attempt to set controller to zero address should revert
        vm.expectRevert(ETHRegistry.InvalidEjectionController.selector);
        registry.setEjectionController(IEjectionController(address(0)));
    }
} 