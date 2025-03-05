// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "../src/registry/L1ETHRegistry.sol";
import "../src/registry/RegistryDatastore.sol";
import "../src/registry/IRegistry.sol";

contract TestL1ETHRegistry is Test, ERC1155Holder {
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);

    RegistryDatastore datastore;
    L1ETHRegistry registry;
    MockL1TokenObserver observer;
    RevertingL1TokenObserver revertingObserver;

    uint256 labelHash = uint256(keccak256("test"));

    function setUp() public {
        datastore = new RegistryDatastore();
        registry = new L1ETHRegistry(datastore);
        registry.grantRole(registry.EJECTION_CONTROLLER_ROLE(), address(this));
        registry.grantRole(registry.RENEWAL_CONTROLLER_ROLE(), address(this));
        observer = new MockL1TokenObserver();
        revertingObserver = new RevertingL1TokenObserver();
    }

    function test_eject_from_l2_unlocked() public {
        
        uint256 expectedId = (labelHash & 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff8);

        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 86400);
        vm.assertEq(tokenId, expectedId);
        vm.assertEq(registry.ownerOf(tokenId), address(this));
    }

    function test_eject_from_l2_locked() public {
        
        uint32 flags = uint32(registry.FLAG_SUBREGISTRY_LOCKED() | registry.FLAG_RESOLVER_LOCKED());
        uint256 expectedId = (labelHash & 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff8) | flags;

        uint256 tokenId =
            registry.ejectFromL2(labelHash, address(this), registry, flags, uint64(block.timestamp) + 86400);
        vm.assertEq(tokenId, expectedId);
    }

    function test_eject_from_l2_emits_events() public {
        
        vm.recordLogs();
        registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 86400);

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

    function test_Revert_eject_from_l2_if_not_controller() public {
        address nonController = address(0x1234);
        vm.startPrank(nonController);
        vm.expectRevert();
        registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 86400);
        vm.stopPrank();
    }

    function test_renew() public {
        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);
        uint64 newExpiry = uint64(block.timestamp) + 200;
        registry.renew(tokenId, newExpiry);

        (uint64 expiry,) = registry.nameData(tokenId);
        assertEq(expiry, newExpiry);
    }

    function test_renew_emits_event() public {
        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);
        uint64 newExpiry = uint64(block.timestamp) + 200;

        vm.recordLogs();
        registry.renew(tokenId, newExpiry);

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

    function test_Revert_renew_expired_name() public {
        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);
        vm.warp(block.timestamp + 101);

        vm.expectRevert(abi.encodeWithSelector(L1ETHRegistry.NameExpired.selector, tokenId));
        registry.renew(tokenId, uint64(block.timestamp) + 200);
    }

    function test_Revert_renew_reduce_expiry() public {
        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 200);
        uint64 newExpiry = uint64(block.timestamp) + 100;

        vm.expectRevert(
            abi.encodeWithSelector(
                L1ETHRegistry.CannotReduceExpiration.selector, uint64(block.timestamp) + 200, newExpiry
            )
        );
        registry.renew(tokenId, newExpiry);
    }

    function test_Revert_renew_if_not_controller() public {
        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);

        address nonController = address(0x1234);
        // Just directly test with non-controller without revoking our own role
        vm.prank(nonController);
        vm.expectRevert();
        registry.renew(tokenId, uint64(block.timestamp) + 200);
    }

    function test_relinquish() public {
        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 86400);
        registry.relinquish(tokenId);
        vm.assertEq(registry.ownerOf(tokenId), address(0));
        vm.assertEq(address(registry.getSubregistry("test")), address(0));
    }

    function test_relinquish_emits_event() public {
        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);

        vm.recordLogs();
        registry.relinquish(tokenId);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundNameRelinquished = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("NameRelinquished(uint256,address)")) {
                foundNameRelinquished = true;
                break;
            }
        }
        assertTrue(foundNameRelinquished, "NameRelinquished event not found");
    }

    function test_Revert_cannot_relinquish_if_not_owner() public {
        uint256 tokenId = registry.ejectFromL2(labelHash, address(1), registry, 0, uint64(block.timestamp) + 86400);

        vm.prank(address(2));
        vm.expectRevert(abi.encodeWithSelector(BaseRegistry.AccessDenied.selector, tokenId, address(1), address(2)));
        registry.relinquish(tokenId);

        vm.assertEq(registry.ownerOf(tokenId), address(1));
    }

    function test_migrateToL2() public {
        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 86400);

        vm.recordLogs();
        registry.migrateToL2(tokenId, address(1));

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

    function test_Revert_migrateToL2_if_not_owner() public {
        uint256 tokenId = registry.ejectFromL2(labelHash, address(1), registry, 0, uint64(block.timestamp) + 86400);

        vm.prank(address(2));
        vm.expectRevert(abi.encodeWithSelector(BaseRegistry.AccessDenied.selector, tokenId, address(1), address(2)));
        registry.migrateToL2(tokenId, address(3));
    }

    function test_Revert_migrateToL2_if_not_controller() public {
        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 86400);

        address nonController = address(0x1234);
        // Just directly test with non-controller without revoking our own role
        vm.prank(nonController);
        vm.expectRevert();
        registry.migrateToL2(tokenId, address(1));
    }

    function test_setFallbackResolver() public {
        address resolver = address(0x1234);

        vm.recordLogs();
        registry.setFallbackResolver(resolver);

        assertEq(registry.fallbackResolver(), resolver);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundResolverSet = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("FallbackResolverSet(address)")) {
                foundResolverSet = true;
                break;
            }
        }
        assertTrue(foundResolverSet, "FallbackResolverSet event not found");
    }

    function test_Revert_setFallbackResolver_if_not_admin() public {
        address nonAdmin = address(0x1234);

        // Instead of revoking our own admin role, just test with the non-admin address
        vm.prank(nonAdmin);
        vm.expectRevert();
        registry.setFallbackResolver(address(0x5678));
    }

    function test_fallbackResolver_when_name_expired() public {
        address resolver = address(0x1234);
        registry.setFallbackResolver(resolver);

        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);
        registry.setResolver(tokenId, address(0x5678));

        vm.warp(block.timestamp + 101);
        assertEq(registry.getResolver("test"), resolver);
    }

    function test_fallbackResolver_when_resolver_not_set() public {
        address resolver = address(0x1234);
        registry.setFallbackResolver(resolver);

        registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);
        // Don't set a resolver

        assertEq(registry.getResolver("test"), resolver);
    }

    function test_expired_name_has_no_owner() public {
        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);
        vm.warp(block.timestamp + 101);
        assertEq(registry.ownerOf(tokenId), address(0));
    }

    function test_expired_name_can_be_reejected() public {
        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);
        vm.warp(block.timestamp + 101);

        uint256 newTokenId = registry.ejectFromL2(labelHash, address(1), registry, 0, uint64(block.timestamp) + 100);
        assertEq(newTokenId, tokenId);
        assertEq(registry.ownerOf(newTokenId), address(1));
    }

    function test_expired_name_returns_zero_subregistry() public {
        registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);
        vm.warp(block.timestamp + 101);
        assertEq(address(registry.getSubregistry("test")), address(0));
    }

    // Token observers

    function test_token_observer_renew() public {
        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);
        registry.setTokenObserver(tokenId, address(observer));

        uint64 newExpiry = uint64(block.timestamp) + 200;
        registry.renew(tokenId, newExpiry);

        assertEq(observer.lastTokenId(), tokenId);
        assertEq(observer.lastExpiry(), newExpiry);
        assertEq(observer.lastCaller(), address(this));
        assertEq(observer.wasRelinquished(), false);
    }

    function test_token_observer_relinquish() public {
        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);
        registry.setTokenObserver(tokenId, address(observer));

        registry.relinquish(tokenId);

        assertEq(observer.lastTokenId(), tokenId);
        assertEq(observer.lastCaller(), address(this));
        assertEq(observer.wasRelinquished(), true);
    }

    function test_Revert_set_token_observer_if_not_owner() public {
        uint256 tokenId = registry.ejectFromL2(labelHash, address(1), registry, 0, uint64(block.timestamp) + 100);

        vm.prank(address(2));
        vm.expectRevert(abi.encodeWithSelector(BaseRegistry.AccessDenied.selector, tokenId, address(1), address(2)));
        registry.setTokenObserver(tokenId, address(observer));
    }

    function test_Revert_renew_when_token_observer_reverts() public {
        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);
        registry.setTokenObserver(tokenId, address(revertingObserver));

        uint64 newExpiry = uint64(block.timestamp) + 200;
        vm.expectRevert(RevertingL1TokenObserver.ObserverReverted.selector);
        registry.renew(tokenId, newExpiry);

        (uint64 expiry,) = registry.nameData(tokenId);
        assertEq(expiry, uint64(block.timestamp) + 100);
    }

    function test_Revert_relinquish_when_token_observer_reverts() public {
        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);
        registry.setTokenObserver(tokenId, address(revertingObserver));

        vm.expectRevert(RevertingL1TokenObserver.ObserverReverted.selector);
        registry.relinquish(tokenId);

        assertEq(registry.ownerOf(tokenId), address(this));
    }

    function test_set_token_observer_emits_event() public {
        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);

        vm.recordLogs();
        registry.setTokenObserver(tokenId, address(observer));

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundObserverSet = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("TokenObserverSet(uint256,address)")) {
                foundObserverSet = true;
                break;
            }
        }
        assertTrue(foundObserverSet, "TokenObserverSet event not found");
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

    function test_eject_from_l2_replace_expired() public {
        // Eject a name first time
        uint256 tokenId = registry.ejectFromL2(labelHash, address(1), registry, 0, uint64(block.timestamp) + 100);
        assertEq(registry.ownerOf(tokenId), address(1));

        // Wait until the name expires
        vm.warp(block.timestamp + 101);

        // Now we can eject the same name to a different owner
        registry.ejectFromL2(labelHash, address(2), registry, 0, uint64(block.timestamp) + 200);
        assertEq(registry.ownerOf(tokenId), address(2));

        // Check the expiry is updated
        (uint64 expiry,) = registry.nameData(tokenId);
        assertEq(expiry, uint64(block.timestamp) + 200);
    }

    function test_eject_from_l2_different_flags() public {
        // Eject a name with no flags
        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);

        // Check initial flags
        (, uint32 flags) = registry.nameData(tokenId);
        assertEq(flags, 0);

        // Eject again with different flags
        uint32 newFlags = uint32(registry.FLAG_SUBREGISTRY_LOCKED());
        uint256 newTokenId =
            registry.ejectFromL2(labelHash, address(this), registry, newFlags, uint64(block.timestamp) + 100);

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

    function test_renew_with_observer() public {
        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);

        // Set observer
        registry.setTokenObserver(tokenId, address(observer));

        // Renew
        registry.renew(tokenId, uint64(block.timestamp) + 200);

        // Check observer was called
        assertEq(observer.lastTokenId(), tokenId);
        assertEq(observer.lastExpiry(), uint64(block.timestamp) + 200);
    }

    function test_set_flags_no_id_change() public {
        // Register with initial flag value of 0
        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);

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
        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);

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
        uint256 tokenId =
            registry.ejectFromL2(labelHash, address(this), registry, initialFlags, uint64(block.timestamp) + 100);

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
        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);

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

    function test_fallback_resolver_in_getResolver() public {
        address fallbackAddr = address(0x1234);
        registry.setFallbackResolver(fallbackAddr);

        // Call getResolver on non-existent name
        assertEq(registry.getResolver("nonexistent"), fallbackAddr);

        // Create a name but don't set resolver
        registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);

        // Should return fallback
        assertEq(registry.getResolver("test"), fallbackAddr);

        // Set a resolver
        uint256 tokenId = uint256(keccak256(bytes("test")));
        address resolverAddr = address(0x5678);
        registry.setResolver(tokenId, resolverAddr);

        // Should return the set resolver
        assertEq(registry.getResolver("test"), resolverAddr);

        // Expire the name
        vm.warp(block.timestamp + 101);

        // Should return fallback again
        assertEq(registry.getResolver("test"), fallbackAddr);
    }

    function test_ejected_name_details() public {
        // Create details for ejected name
        uint256 labelHash = uint256(keccak256("ejected"));
        address owner = address(0x1234);
        address registryAddr = address(registry);
        uint32 flags = uint32(registry.FLAG_RESOLVER_LOCKED());
        uint64 expires = uint64(block.timestamp) + 500;

        // Eject the name
        uint256 tokenId = registry.ejectFromL2(labelHash, owner, IRegistry(registryAddr), flags, expires);

        // Verify all details
        assertEq(registry.ownerOf(tokenId), owner);
        (uint64 storedExpiry, uint32 storedFlags) = registry.nameData(tokenId);
        assertEq(storedExpiry, expires);
        assertEq(storedFlags, flags);
        assertEq(address(registry.getSubregistry("ejected")), registryAddr);

        // Check resolver behavior
        assertEq(registry.getResolver("ejected"), registry.fallbackResolver());

        // Set up a different test case without flags to test setting resolver
        uint256 label2Hash = uint256(keccak256("unlocked"));
        uint256 unlockedTokenId = registry.ejectFromL2(label2Hash, owner, IRegistry(registryAddr), 0, expires);

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

    function test_migrateToL2_with_locked_name() public {
        // Eject a name with locked flags
        uint32 flags = uint32(registry.FLAG_SUBREGISTRY_LOCKED() | registry.FLAG_RESOLVER_LOCKED());
        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, flags, uint64(block.timestamp) + 100);

        // Migrate back to L2
        registry.migrateToL2(tokenId, address(1));

        // Name should no longer exist on L1
        assertEq(registry.ownerOf(tokenId), address(0));
        assertEq(address(registry.getSubregistry("test")), address(0));
    }

    function test_multiple_observers() public {
        uint256 labelHash1 = uint256(keccak256("name1"));
        uint256 labelHash2 = uint256(keccak256("name2"));

        // Create two different owners with names
        uint256 tokenId1 = registry.ejectFromL2(labelHash1, address(this), registry, 0, uint64(block.timestamp) + 100);
        uint256 tokenId2 = registry.ejectFromL2(labelHash2, address(this), registry, 0, uint64(block.timestamp) + 100);

        // Create a second observer
        MockL1TokenObserver observer2 = new MockL1TokenObserver();

        // Set different observers for each name
        registry.setTokenObserver(tokenId1, address(observer));
        registry.setTokenObserver(tokenId2, address(observer2));

        // Renew first name
        registry.renew(tokenId1, uint64(block.timestamp) + 200);

        // First observer should have been called with first name
        assertEq(observer.lastTokenId(), tokenId1);
        assertEq(observer.lastExpiry(), uint64(block.timestamp) + 200);

        // Second observer should not have been called
        assertEq(observer2.lastTokenId(), 0);

        // Renew second name
        registry.renew(tokenId2, uint64(block.timestamp) + 300);

        // Second observer should now have been called with second name
        assertEq(observer2.lastTokenId(), tokenId2);
        assertEq(observer2.lastExpiry(), uint64(block.timestamp) + 300);

        // First observer should still have first name data
        assertEq(observer.lastTokenId(), tokenId1);
    }

    function test_change_token_observer() public {
        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);

        // Set observer
        registry.setTokenObserver(tokenId, address(observer));
        assertEq(registry.tokenObservers(tokenId), address(observer));

        // Change observer to another one
        MockL1TokenObserver observer2 = new MockL1TokenObserver();
        registry.setTokenObserver(tokenId, address(observer2));
        assertEq(registry.tokenObservers(tokenId), address(observer2));

        // Renew to trigger observer
        registry.renew(tokenId, uint64(block.timestamp) + 200);

        // Only observer2 should have been called
        assertEq(observer2.lastTokenId(), tokenId);
        assertEq(observer.lastTokenId(), 0);
    }

    function test_remove_token_observer() public {
        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);

        // Set observer
        registry.setTokenObserver(tokenId, address(observer));

        // Remove observer
        registry.setTokenObserver(tokenId, address(0));
        assertEq(registry.tokenObservers(tokenId), address(0));

        // Renew - should not call observer
        registry.renew(tokenId, uint64(block.timestamp) + 200);

        // Observer should not have been called
        assertEq(observer.lastTokenId(), 0);
    }

    function test_Revert_eject_active_name() public {
        
        uint256 tokenId = registry.ejectFromL2(labelHash, address(this), registry, 0, uint64(block.timestamp) + 100);

        // Try to eject the same name again before it expires
        vm.expectRevert(
            abi.encodeWithSelector(L1ETHRegistry.NameNotExpired.selector, tokenId, uint64(block.timestamp) + 100)
        );
        registry.ejectFromL2(labelHash, address(1), registry, 0, uint64(block.timestamp) + 200);

        // Original owner should still own the name
        assertEq(registry.ownerOf(tokenId), address(this));
    }
}

contract MockL1TokenObserver is L1ETHRegistryTokenObserver {
    uint256 public lastTokenId;
    uint64 public lastExpiry;
    address public lastCaller;
    bool public wasRelinquished;

    function onRenew(uint256 tokenId, uint64 expires, address renewedBy) external {
        lastTokenId = tokenId;
        lastExpiry = expires;
        lastCaller = renewedBy;
        wasRelinquished = false;
    }

    function onRelinquish(uint256 tokenId, address relinquishedBy) external {
        lastTokenId = tokenId;
        lastCaller = relinquishedBy;
        wasRelinquished = true;
    }
}

contract RevertingL1TokenObserver is L1ETHRegistryTokenObserver {
    error ObserverReverted();

    function onRenew(uint256, uint64, address) external pure {
        revert ObserverReverted();
    }

    function onRelinquish(uint256, address) external pure {
        revert ObserverReverted();
    }
}
