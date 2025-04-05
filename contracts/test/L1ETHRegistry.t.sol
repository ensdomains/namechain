// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "../src/L1/L1ETHRegistry.sol";
import "../src/common/RegistryDatastore.sol";
import "../src/common/IRegistry.sol";
import "../src/L1/IL1EjectionController.sol";

contract TestL1ETHRegistry is Test, ERC1155Holder {
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);

    RegistryDatastore datastore;
    L1ETHRegistry registry;
    MockEjectionController ejectionController;

    uint256 labelHash = uint256(keccak256("test"));

    function setUp() public {
        datastore = new RegistryDatastore();
        ejectionController = new MockEjectionController();
        registry = new L1ETHRegistry(datastore, address(ejectionController));
    }

    function test_eject_from_namechain_unlocked() public {
        uint256 expectedId = (labelHash & 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff8);

        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, 0, uint64(block.timestamp) + 86400);
        
        vm.assertEq(tokenId, expectedId);
        vm.assertEq(registry.ownerOf(tokenId), address(this));
    }

    function test_eject_from_namechain_locked() public {
        uint32 flags = uint32(registry.FLAG_SUBREGISTRY_LOCKED() | registry.FLAG_RESOLVER_LOCKED());
        uint256 expectedId = (labelHash & 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff8) | flags;

        vm.prank(address(ejectionController));
        uint256 tokenId =
            registry.ejectFromNamechain(labelHash, address(this), registry, flags, uint64(block.timestamp) + 86400);
            
        vm.assertEq(tokenId, expectedId);
    }

    function test_eject_from_namechain_emits_events() public {
        vm.recordLogs();
        
        vm.prank(address(ejectionController));
        registry.ejectFromNamechain(labelHash, address(this), registry, 0, uint64(block.timestamp) + 86400);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        // There are 3 events: TransferSingle, onERC1155Received callback, SubregistryUpdate, NameEjected
        // We need to verify NameEjected is emitted
        bool foundNameEjected = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("NameEjected(uint256,address,uint64)")) {
                foundNameEjected = true;
                break;
            }
        }
        assertTrue(foundNameEjected, "NameEjected event not found");
    }

    function test_Revert_eject_from_namechain_if_not_controller() public {
        address nonController = address(0x1234);
        vm.startPrank(nonController);
        vm.expectRevert(L1ETHRegistry.OnlyEjectionController.selector);
        registry.ejectFromNamechain(labelHash, address(this), registry, 0, uint64(block.timestamp) + 86400);
        vm.stopPrank();
    }

    function test_updateExpiration() public {
        // First eject a name
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);
        
        uint64 newExpiry = uint64(block.timestamp) + 200;
        
        // Prank as ejection controller to update expiration
        vm.prank(address(ejectionController));
        registry.updateExpiration(tokenId, newExpiry);

        (uint64 expiry,) = registry.nameData(tokenId);
        assertEq(expiry, newExpiry);
    }

    function test_updateExpiration_emits_event() public {
        // First eject a name
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);
        
        uint64 newExpiry = uint64(block.timestamp) + 200;

        vm.recordLogs();
        
        // Prank as ejection controller to update expiration
        vm.prank(address(ejectionController));
        registry.updateExpiration(tokenId, newExpiry);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundNameRenewed = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("NameRenewed(uint256,uint64,address)")) {
                foundNameRenewed = true;
                break;
            }
        }
        assertTrue(foundNameRenewed, "NameRenewed event not found");
    }

    function test_Revert_updateExpiration_expired_name() public {
        // First eject a name
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);
        
        vm.warp(block.timestamp + 101);

        vm.prank(address(ejectionController));
        vm.expectRevert(abi.encodeWithSelector(L1ETHRegistry.NameExpired.selector, tokenId));
        registry.updateExpiration(tokenId, uint64(block.timestamp) + 200);
    }

    function test_Revert_updateExpiration_reduce_expiry() public {
        // First eject a name
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, 0, uint64(block.timestamp) + 200);
        
        uint64 newExpiry = uint64(block.timestamp) + 100;

        vm.prank(address(ejectionController));
        vm.expectRevert(
            abi.encodeWithSelector(
                L1ETHRegistry.CannotReduceExpiration.selector, uint64(block.timestamp) + 200, newExpiry
            )
        );
        registry.updateExpiration(tokenId, newExpiry);
    }

    function test_Revert_updateExpiration_if_not_controller() public {
        // First eject a name
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);
        
        uint64 newExpiry = uint64(block.timestamp) + 200;
        
        address nonController = address(0x1234);
        vm.startPrank(nonController);
        vm.expectRevert(L1ETHRegistry.OnlyEjectionController.selector);
        registry.updateExpiration(tokenId, newExpiry);
        vm.stopPrank();
    }

    function test_migrateToNamechain() public {
        // First eject a name
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, 0, uint64(block.timestamp) + 86400);

        vm.recordLogs();
        registry.migrateToNamechain(tokenId, address(1), address(0), "");

        vm.assertEq(registry.ownerOf(tokenId), address(0));

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundNameMigrated = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("NameMigratedToL2(uint256,address)")) {
                foundNameMigrated = true;
                break;
            }
        }
        assertTrue(foundNameMigrated, "NameMigratedToL2 event not found");
    }

    function test_Revert_migrateToNamechain_if_not_owner() public {
        // First eject a name
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(1), registry, 0, uint64(block.timestamp) + 86400);

        vm.prank(address(2));
        vm.expectRevert(abi.encodeWithSelector(BaseRegistry.AccessDenied.selector, tokenId, address(1), address(2)));
        registry.migrateToNamechain(tokenId, address(3), address(0), "");
    }

    function test_expired_name_has_no_owner() public {
        // First eject a name
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);
        
        vm.warp(block.timestamp + 101);
        assertEq(registry.ownerOf(tokenId), address(0));
    }

    function test_expired_name_can_be_reejected() public {
        // First eject a name
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);
        vm.warp(block.timestamp + 101);

        vm.prank(address(ejectionController));
        uint256 newTokenId = registry.ejectFromNamechain(labelHash, address(1), registry, 0, uint64(block.timestamp) + 100);
        assertEq(newTokenId, tokenId);
        assertEq(registry.ownerOf(newTokenId), address(1));
    }

    function test_expired_name_returns_zero_subregistry() public {
        // First eject a name
        vm.prank(address(ejectionController));
        registry.ejectFromNamechain(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);
        
        vm.warp(block.timestamp + 101);
        assertEq(address(registry.getSubregistry("test")), address(0));
    }

    function test_expired_name_returns_zero_resolver() public {
        // First eject a name
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);
        registry.setResolver(tokenId, address(0x5678));

        // Before expiry, returns the set resolver
        assertEq(registry.getResolver("test"), address(0x5678));

        // After expiry, returns address(0)
        vm.warp(block.timestamp + 101);
        assertEq(registry.getResolver("test"), address(0));
    }

    // Test ejection controller change
    function test_setEjectionController() public {
        MockEjectionController newController = new MockEjectionController();
        
        // Record logs to verify event emission
        vm.recordLogs();
        
        registry.setEjectionController(address(newController));
        
        // Verify controller was updated
        assertEq(address(registry.ejectionController()), address(newController));
        
        // Verify event was emitted
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundControllerChanged = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("EjectionControllerChanged(address,address)")) {
                foundControllerChanged = true;
                break;
            }
        }
        assertTrue(foundControllerChanged, "EjectionControllerChanged event not found");
    }
    
    function test_Revert_setEjectionController_if_not_admin() public {
        address nonAdmin = address(0x1234);
        vm.startPrank(nonAdmin);
        vm.expectRevert();
        registry.setEjectionController(address(0x5678));
        vm.stopPrank();
    }
    
    function test_Revert_setEjectionController_zero_address() public {
        vm.expectRevert("Ejection controller cannot be empty");
        registry.setEjectionController(address(0));
    }

    function test_supportsInterface() public view {
        // Test IRegistry interface
        bytes4 iRegistryInterfaceId = type(IRegistry).interfaceId;
        assertTrue(registry.supportsInterface(iRegistryInterfaceId));

        // Test ERC1155 interface
        bytes4 erc1155InterfaceId = 0xd9b67a26; // ERC1155 interface ID
        assertTrue(registry.supportsInterface(erc1155InterfaceId));

        // Test AccessControl interface
        bytes4 accessControlInterfaceId = 0x7965db0b; // AccessControl interface ID
        assertTrue(registry.supportsInterface(accessControlInterfaceId));

        // Test unsupported interface
        bytes4 unsupportedInterfaceId = 0x12345678;
        assertFalse(registry.supportsInterface(unsupportedInterfaceId));
    }

    function test_eject_from_namechain_replace_expired() public {
        // First eject a name
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(1), registry, 0, uint64(block.timestamp) + 100);
        assertEq(registry.ownerOf(tokenId), address(1));

        // Wait until the name expires
        vm.warp(block.timestamp + 101);

        // Now we can eject the same name to a different owner
        vm.prank(address(ejectionController));
        registry.ejectFromNamechain(labelHash, address(2), registry, 0, uint64(block.timestamp) + 200);
        assertEq(registry.ownerOf(tokenId), address(2));

        // Check the expiry is updated
        (uint64 expiry,) = registry.nameData(tokenId);
        assertEq(expiry, uint64(block.timestamp) + 200);
    }

    function test_eject_from_namechain_different_flags() public {
        // Eject a name with no flags
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);

        // Check initial flags
        (, uint32 flags) = registry.nameData(tokenId);
        assertEq(flags, 0);

        // Eject again with different flags
        uint32 newFlags = uint32(registry.FLAG_SUBREGISTRY_LOCKED());
        
        vm.prank(address(ejectionController));
        uint256 newTokenId =
            registry.ejectFromNamechain(labelHash, address(this), registry, newFlags, uint64(block.timestamp) + 100);

        // The token ID should have changed
        assertFalse(tokenId == newTokenId);

        // New flags should be set
        (, flags) = registry.nameData(newTokenId);
        assertEq(flags, newFlags);
    }

    function test_uri() public view {
        // Test that URI returns empty string
        assertEq(registry.uri(1), "");
    }

    function test_set_flags_no_id_change() public {
        // Register with initial flag value of 0
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);

        // Setting FLAG_RESOLVER_LOCKED (value 2)
        uint96 flags = registry.FLAG_RESOLVER_LOCKED();
        uint256 newTokenId = registry.setFlags(tokenId, flags);

        // The token ID WILL change because the flags are reflected in the token ID
        // Calculate the expected new token ID
        uint256 expectedNewTokenId = (tokenId & ~uint256(registry.FLAGS_MASK())) | flags;
        assertEq(newTokenId, expectedNewTokenId);

        // Check that the flag is correctly set
        (, uint32 storedFlags) = registry.nameData(newTokenId);
        assertEq(storedFlags, flags);

        // Verify old token doesn't exist and new one does
        assertEq(registry.ownerOf(tokenId), address(0));
        assertEq(registry.ownerOf(newTokenId), address(this));
    }

    function test_set_flags_with_id_change() public {
        // Register with initial flag value of 0
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);

        // Setting flags that affect token ID (lower 3 bits)
        uint96 flags = 0x7; // Use all 3 bits that affect token ID
        uint256 newTokenId = registry.setFlags(tokenId, flags);

        // Token ID should change
        assertNotEq(tokenId, newTokenId);

        // New token should exist
        assertEq(registry.ownerOf(newTokenId), address(this));

        // Old token should not exist
        assertEq(registry.ownerOf(tokenId), address(0));
    }

    function test_cannot_unlock_locked_flags() public {
        // Register with FLAG_FLAGS_LOCKED
        uint32 initialFlags = uint32(registry.FLAG_FLAGS_LOCKED());
        
        vm.prank(address(ejectionController));
        uint256 tokenId =
            registry.ejectFromNamechain(labelHash, address(this), registry, initialFlags, uint64(block.timestamp) + 100);

        // Try to clear flags - should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseRegistry.InvalidSubregistryFlags.selector, tokenId, registry.FLAG_FLAGS_LOCKED(), 0
            )
        );
        registry.setFlags(tokenId, 0);

        // Verify flags didn't change
        (, uint32 storedFlags) = registry.nameData(tokenId);
        assertEq(storedFlags, initialFlags);
    }

    function test_complex_flag_operations() public {
        // Start with no flags
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);

        // Add RESOLVER_LOCKED
        uint96 flags = registry.FLAG_RESOLVER_LOCKED();
        uint256 newTokenId = registry.setFlags(tokenId, flags);

        // Update our tokenId variable to use the new ID
        tokenId = newTokenId;

        // Add SUBREGISTRY_LOCKED
        flags |= registry.FLAG_SUBREGISTRY_LOCKED();
        newTokenId = registry.setFlags(tokenId, flags);

        // Check both flags are set
        (, uint32 storedFlags) = registry.nameData(newTokenId);
        assertTrue((storedFlags & registry.FLAG_RESOLVER_LOCKED()) != 0);
        assertTrue((storedFlags & registry.FLAG_SUBREGISTRY_LOCKED()) != 0);

        // Try to set resolver - should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseRegistry.InvalidSubregistryFlags.selector, newTokenId, registry.FLAG_RESOLVER_LOCKED(), 0
            )
        );
        registry.setResolver(newTokenId, address(0x1234));

        // Try to set subregistry - should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseRegistry.InvalidSubregistryFlags.selector, newTokenId, registry.FLAG_SUBREGISTRY_LOCKED(), 0
            )
        );
        registry.setSubregistry(newTokenId, IRegistry(address(0x1234)));
    }

    function test_ejected_name_details() public {
        // Create details for ejected name
        uint256 labelHash_ = uint256(keccak256("ejected"));
        address owner = address(0x1234);
        address registryAddr = address(registry);
        uint32 flags = uint32(registry.FLAG_RESOLVER_LOCKED());
        uint64 expires = uint64(block.timestamp) + 500;

        // Eject the name
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash_, owner, IRegistry(registryAddr), flags, expires);

        // Verify all details
        assertEq(registry.ownerOf(tokenId), owner);
        (uint64 storedExpiry, uint32 storedFlags) = registry.nameData(tokenId);
        assertEq(storedExpiry, expires);
        assertEq(storedFlags, flags);
        assertEq(address(registry.getSubregistry("ejected")), registryAddr);

        // Set up a different test case without flags to test setting resolver
        vm.prank(address(ejectionController));
        uint256 label2Hash = uint256(keccak256("unlocked"));
        uint256 unlockedTokenId = registry.ejectFromNamechain(label2Hash, owner, IRegistry(registryAddr), 0, expires);

        // Try to set a resolver for the unlocked name - should succeed
        vm.startPrank(owner);
        address resolverAddr = address(0x5678);
        registry.setResolver(unlockedTokenId, resolverAddr);
        assertEq(registry.getResolver("unlocked"), resolverAddr);

        // Now try to set resolver for the locked name - should fail with InvalidSubregistryFlags
        vm.expectRevert(abi.encodeWithSelector(BaseRegistry.InvalidSubregistryFlags.selector, tokenId, flags, 0));
        registry.setResolver(tokenId, resolverAddr);
        vm.stopPrank();
    }

    function test_migrateToNamechain_with_locked_name() public {
        // Eject a name with locked flags
        uint32 flags = uint32(registry.FLAG_SUBREGISTRY_LOCKED() | registry.FLAG_RESOLVER_LOCKED());
        
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, flags, uint64(block.timestamp) + 100);

        // Migrate back to Namechain
        registry.migrateToNamechain(tokenId, address(1), address(0), "");

        // Name should no longer exist on L1
        assertEq(registry.ownerOf(tokenId), address(0));
        assertEq(address(registry.getSubregistry("test")), address(0));
    }

    function test_Revert_eject_active_name() public {
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);

        // Try to eject the same name again before it expires
        vm.prank(address(ejectionController));
        vm.expectRevert(
            abi.encodeWithSelector(L1ETHRegistry.NameNotExpired.selector, tokenId, uint64(block.timestamp) + 100)
        );
        registry.ejectFromNamechain(labelHash, address(1), registry, 0, uint64(block.timestamp) + 200);

        // Original owner should still own the name
        assertEq(registry.ownerOf(tokenId), address(this));
    }

    function test_migrateToNamechain_calls_controller() public {
        // First eject a name
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);
        address l2Owner = address(0x1234);
        address l2Subregistry = address(0x5678);
        bytes memory data = hex"deadbeef";
        
        // Create a new ejection controller to track the migration call
        MockEjectionController newController = new MockEjectionController();
        
        // Set the new controller
        registry.setEjectionController(address(newController));
        
        // Call migrate
        registry.migrateToNamechain(tokenId, l2Owner, l2Subregistry, data);
        
        // Verify controller was called correctly
        (uint256 lastTokenId, address lastL2Owner, address lastL2Subregistry, bytes memory lastData) = newController.getLastMigration();
        assertEq(lastTokenId, tokenId);
        assertEq(lastL2Owner, l2Owner);
        assertEq(lastL2Subregistry, l2Subregistry);
        assertEq(lastData, data);
    }

    function test_ejection_controller_sync_renewal() public {
        // First eject a name
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);
        
        // Create a new controller to specifically test the syncRenewalFromL2 flow
        MockEjectionController newController = new MockEjectionController();
        
        // Set the new controller
        registry.setEjectionController(address(newController));
        
        // New expiry time
        uint64 newExpiry = uint64(block.timestamp) + 300;
        
        // Call syncRenewalFromL2 on the controller
        newController.triggerSyncRenewalFromL2(registry, tokenId, newExpiry);
        
        // Verify expiry was updated
        (uint64 expiry,) = registry.nameData(tokenId);
        assertEq(expiry, newExpiry);
    }
}

contract MockEjectionController is IL1EjectionController {
    // Storage for last migration call
    uint256 private _lastTokenId;
    address private _lastL2Owner;
    address private _lastL2Subregistry;
    bytes private _lastData;

    function migrateToNamechain(uint256 tokenId, address l2Owner, address l2Subregistry, bytes memory data) external override {
        _lastTokenId = tokenId;
        _lastL2Owner = l2Owner;
        _lastL2Subregistry = l2Subregistry;
        _lastData = data;
    }

    function completeEjection(
        uint256,
        address,
        address,
        uint32,
        uint64,
        bytes memory
    ) external override {}

    function syncRenewalFromL2(uint256 tokenId, uint64 newExpiry) external override {
        // This would be called by the L2 bridge to update expiry on L1
        L1ETHRegistry(msg.sender).updateExpiration(tokenId, newExpiry);
    }
    
    // Method to trigger a renewal from L2 for testing
    function triggerSyncRenewalFromL2(L1ETHRegistry registry, uint256 tokenId, uint64 newExpiry) external {
        registry.updateExpiration(tokenId, newExpiry);
    }
    
    // Method to retrieve the last migration details for assertions
    function getLastMigration() external view returns (uint256, address, address, bytes memory) {
        return (_lastTokenId, _lastL2Owner, _lastL2Subregistry, _lastData);
    }
}
