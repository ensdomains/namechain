// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "../src/L1/L1ETHRegistry.sol";
import "../src/common/RegistryDatastore.sol";
import "../src/common/IRegistry.sol";
import "../src/L1/IL1EjectionController.sol";
import {EnhancedAccessControl} from "../src/common/EnhancedAccessControl.sol";
import "../src/common/IRegistryMetadata.sol";
import {RegistryRolesMixin} from "../src/common/RegistryRolesMixin.sol";
import "../src/common/BaseRegistry.sol";
import "../src/common/IStandardRegistry.sol";
import "../src/common/ETHRegistry.sol";

contract MockRegistryMetadata is IRegistryMetadata {
    function tokenUri(uint256) external pure override returns (string memory) {
        return "";
    }
}

contract TestL1ETHRegistry is Test, ERC1155Holder, RegistryRolesMixin, EnhancedAccessControl {
    RegistryDatastore datastore;
    L1ETHRegistry registry;
    MockEjectionController ejectionController;
    MockRegistryMetadata registryMetadata;
    address constant MOCK_RESOLVER = address(0xabcd);

    uint256 labelHash = uint256(keccak256("test"));

    function supportsInterface(bytes4 /*interfaceId*/) public pure override(ERC1155Holder, EnhancedAccessControl) returns (bool) {
        return true;
    }
    
    function setUp() public {
        datastore = new RegistryDatastore();
        ejectionController = new MockEjectionController();
        registryMetadata = new MockRegistryMetadata();
        registry = new L1ETHRegistry(datastore, registryMetadata, address(ejectionController));
    }

    function test_eject_from_namechain_unlocked() public {
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), IRegistry(address(registry)), MOCK_RESOLVER, uint64(block.timestamp) + 86400);
        
        assertEq(registry.ownerOf(tokenId), address(this));
    }

    function test_eject_from_namechain_basic() public {
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), IRegistry(address(registry)), MOCK_RESOLVER, uint64(block.timestamp) + 86400);
        
        assertEq(registry.ownerOf(tokenId), address(this));
        
        assertEq(address(registry.getSubregistry("test")), address(registry));

        assertEq(registry.getResolver("test"), MOCK_RESOLVER);
    }

    function test_eject_from_namechain_emits_events() public {
        vm.recordLogs();
        
        vm.prank(address(ejectionController));
        registry.ejectFromNamechain(labelHash, address(this), IRegistry(address(registry)), MOCK_RESOLVER, uint64(block.timestamp) + 86400);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundNameEjected = false;
        bytes32 expectedSig = keccak256("NameEjectedFromL2(uint256,address,address,address,uint64)");
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == expectedSig) {
                foundNameEjected = true;
                break;
            }
        }
        assertTrue(foundNameEjected, "NameEjectedFromL2 event not found");
    }

    function test_Revert_eject_from_namechain_if_not_controller() public {
        address nonController = address(0x1234);
        vm.startPrank(nonController);
        vm.expectRevert(ETHRegistry.OnlyEjectionController.selector);
        registry.ejectFromNamechain(labelHash, address(this), IRegistry(address(registry)), MOCK_RESOLVER, uint64(block.timestamp) + 86400);
        vm.stopPrank();
    }

    function test_updateExpiration() public {
        vm.prank(address(ejectionController));
        uint64 expiryTime = uint64(block.timestamp) + 100;
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), IRegistry(address(registry)), MOCK_RESOLVER, expiryTime);
        
        // Verify initial expiry was set
        (,uint64 initialExpiry,) = datastore.getSubregistry(address(registry), tokenId);
        assertEq(initialExpiry, expiryTime, "Initial expiry not set correctly");
        
        uint64 newExpiry = uint64(block.timestamp) + 200;
        
        vm.prank(address(ejectionController));
        registry.updateExpiration(tokenId, newExpiry);

        // Verify new expiry was set
        (,uint64 updatedExpiry,) = datastore.getSubregistry(address(registry), tokenId);
        assertEq(updatedExpiry, newExpiry, "Expiry was not updated correctly");
    }

    function test_updateExpiration_emits_event() public {
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), IRegistry(address(registry)), MOCK_RESOLVER, uint64(block.timestamp) + 100);
        
        uint64 newExpiry = uint64(block.timestamp) + 200;

        vm.recordLogs();
        
        vm.prank(address(ejectionController));
        registry.updateExpiration(tokenId, newExpiry);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundNameRenewed = false;
        bytes32 expectedSig = keccak256("NameRenewed(uint256,uint64,address)");
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == expectedSig) {
                foundNameRenewed = true;
                break;
            }
        }
        assertTrue(foundNameRenewed, "NameRenewed event not found");
    }

    function test_Revert_updateExpiration_expired_name() public {
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), IRegistry(address(registry)), MOCK_RESOLVER, uint64(block.timestamp) + 100);
        
        vm.warp(block.timestamp + 101);

        vm.prank(address(ejectionController));
        vm.expectRevert(abi.encodeWithSelector(IStandardRegistry.NameExpired.selector, tokenId));
        registry.updateExpiration(tokenId, uint64(block.timestamp) + 200);
    }

    function test_Revert_updateExpiration_reduce_expiry() public {
        vm.prank(address(ejectionController));
        uint64 initialExpiry = uint64(block.timestamp) + 200;
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), IRegistry(address(registry)), MOCK_RESOLVER, initialExpiry);
        
        uint64 newExpiry = uint64(block.timestamp) + 100;

        vm.prank(address(ejectionController));
        vm.expectRevert(
            abi.encodeWithSelector(
                IStandardRegistry.CannotReduceExpiration.selector, initialExpiry, newExpiry
            )
        );
        registry.updateExpiration(tokenId, newExpiry);
    }

    function test_Revert_updateExpiration_if_not_controller() public {
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), IRegistry(address(registry)), MOCK_RESOLVER, uint64(block.timestamp) + 100);
        
        uint64 newExpiry = uint64(block.timestamp) + 200;
        
        address nonController = address(0x1234);
        vm.startPrank(nonController);
        vm.expectRevert(ETHRegistry.OnlyEjectionController.selector);
        registry.updateExpiration(tokenId, newExpiry);
        vm.stopPrank();
    }

    function test_migrateToNamechain() public {
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), IRegistry(address(registry)), MOCK_RESOLVER, uint64(block.timestamp) + 86400);

        address l2Owner = address(1);
        address l2Subregistry = address(2);
        address l2Resolver = address(3);
        bytes memory data = hex"beef";

        vm.recordLogs();
        registry.migrateToNamechain(tokenId, l2Owner, l2Subregistry, l2Resolver, data);

        assertEq(registry.ownerOf(tokenId), address(0));

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundNameMigrated = false;
        bytes32 expectedSig = keccak256("NameMigratedToL2(uint256,address,address,address)");
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == expectedSig) {
                foundNameMigrated = true;
                break;
            }
        }
        assertTrue(foundNameMigrated, "NameMigratedToL2 event not found");

        (uint256 lastTokenId, address lastL2Owner, address lastL2Subregistry, address lastL2Resolver, bytes memory lastData) = ejectionController.getLastMigration();
        assertEq(lastTokenId, tokenId);
        assertEq(lastL2Owner, l2Owner);
        assertEq(lastL2Subregistry, l2Subregistry);
        assertEq(lastL2Resolver, l2Resolver);
        assertEq(lastData, data);
    }

    function test_Revert_migrateToNamechain_if_not_owner() public {
        vm.prank(address(ejectionController));
        address owner = address(1);
        uint256 tokenId = registry.ejectFromNamechain(labelHash, owner, IRegistry(address(registry)), MOCK_RESOLVER, uint64(block.timestamp) + 86400);

        address attacker = address(2);
        vm.startPrank(attacker);
        vm.expectRevert(abi.encodeWithSelector(BaseRegistry.AccessDenied.selector, tokenId, owner, attacker));
        registry.migrateToNamechain(tokenId, address(3), address(4), address(5), "");
        vm.stopPrank();
    }

    function test_expired_name_has_no_owner() public {
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), IRegistry(address(registry)), MOCK_RESOLVER, uint64(block.timestamp) + 100);
        
        vm.warp(block.timestamp + 101);
        assertEq(registry.ownerOf(tokenId), address(0));
    }

    function test_expired_name_can_be_reejected() public {
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), IRegistry(address(registry)), MOCK_RESOLVER, uint64(block.timestamp) + 100);
        
        vm.warp(block.timestamp + 101);
        
        assertEq(registry.ownerOf(tokenId), address(0));
        assertEq(registry.balanceOf(address(this), tokenId), 0); 
        
        bytes32 nameEjectedSig = keccak256("NameEjectedFromL2(uint256,address,address,address,uint64)");
        
        vm.recordLogs();
        
        address newOwner = address(1);
        vm.prank(address(ejectionController));
        uint256 newTokenId = registry.ejectFromNamechain(labelHash, newOwner, IRegistry(address(registry)), MOCK_RESOLVER, uint64(block.timestamp) + 100);
        
        assertEq(newTokenId, tokenId);
        
        assertEq(registry.ownerOf(newTokenId), newOwner);
        assertEq(registry.balanceOf(newOwner, newTokenId), 1);
        
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundNameEjected = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == nameEjectedSig) {
                foundNameEjected = true;
                break;
            }
        }
        assertTrue(foundNameEjected, "NameEjectedFromL2 event not found");
    }

    function test_expired_name_returns_zero_subregistry() public {
        vm.prank(address(ejectionController));
        registry.ejectFromNamechain(labelHash, address(this), IRegistry(address(registry)), MOCK_RESOLVER, uint64(block.timestamp) + 100);
        
        vm.warp(block.timestamp + 101);
        assertEq(address(registry.getSubregistry("test")), address(0));
    }

    function test_expired_name_returns_zero_resolver() public {
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), IRegistry(address(registry)), MOCK_RESOLVER, uint64(block.timestamp) + 100);
        address tempResolver = address(0x5678);
        registry.setResolver(tokenId, tempResolver);

        assertEq(registry.getResolver("test"), tempResolver);

        vm.warp(block.timestamp + 101);
        assertEq(registry.getResolver("test"), address(0));
    }

    function test_setEjectionController() public {
        MockEjectionController newController = new MockEjectionController();
        
        vm.recordLogs();
        
        registry.setEjectionController(address(newController));
        
        assertEq(registry.ejectionController(), address(newController));
        
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundControllerChanged = false;
        bytes32 expectedSig = keccak256("EjectionControllerChanged(address,address)");
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == expectedSig) {
                foundControllerChanged = true;
                break;
            }
        }
        assertTrue(foundControllerChanged, "EjectionControllerChanged event not found");
    }
    
    function test_Revert_setEjectionController_if_not_admin() public {
        address nonAdmin = address(0x1234);
        
        vm.startPrank(nonAdmin);
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, ROOT_RESOURCE, ROLE_SET_EJECTION_CONTROLLER, nonAdmin));
        registry.setEjectionController(vm.addr(0x5678));
        vm.stopPrank();
    }
    
    function test_Revert_setEjectionController_zero_address() public {
        vm.expectRevert(ETHRegistry.InvalidEjectionController.selector);
        registry.setEjectionController(address(0));
    }

    function test_supportsInterface() public view {
        // Check for IRegistry interface support
        bytes4 iRegistryInterfaceId = type(IRegistry).interfaceId;
        assertTrue(registry.supportsInterface(iRegistryInterfaceId), "Should support IRegistry interface");

        // Check for ERC1155 interface support (0xd9b67a26 is the ERC1155 interface ID)
        bytes4 erc1155InterfaceId = 0xd9b67a26;
        assertTrue(registry.supportsInterface(erc1155InterfaceId), "Should support ERC1155 interface");

        // Check rejection of an invalid interface ID
        bytes4 unsupportedInterfaceId = 0x12345678;
        assertFalse(registry.supportsInterface(unsupportedInterfaceId), "Should not support random interface");
    }

    function test_eject_from_namechain_replace_expired() public {
        vm.prank(address(ejectionController));
        uint64 expiry1 = uint64(block.timestamp) + 100;
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), IRegistry(address(registry)), MOCK_RESOLVER, expiry1);
        assertEq(registry.ownerOf(tokenId), address(this), "Owner not set correctly after first ejection");
        
        // Check expiry in datastore directly
        (,uint64 storedExpiry1,) = datastore.getSubregistry(address(registry), tokenId);
        assertEq(storedExpiry1, expiry1, "Expiry not set correctly after first ejection");

        vm.warp(block.timestamp + 101);
        assertEq(registry.ownerOf(tokenId), address(0), "Owner should be zero after expiry");

        address newOwner = address(0xbeef);
        uint64 expiry2 = uint64(block.timestamp) + 200;
        vm.prank(address(ejectionController));
        uint256 newTokenId = registry.ejectFromNamechain(labelHash, newOwner, IRegistry(address(registry)), MOCK_RESOLVER, expiry2);

        assertEq(newTokenId, tokenId, "New token ID should match original token ID");
        assertEq(registry.ownerOf(newTokenId), newOwner, "Owner not set correctly after re-ejection");
        
        // Check expiry in datastore directly
        (,uint64 storedExpiry2,) = datastore.getSubregistry(address(registry), newTokenId);
        assertEq(storedExpiry2, expiry2, "Expiry not set correctly after re-ejection");
    }

    function test_migrateToNamechain_basic() public {
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), IRegistry(address(registry)), MOCK_RESOLVER, uint64(block.timestamp) + 100);

        registry.migrateToNamechain(tokenId, address(1), address(2), address(3), "");

        assertEq(registry.ownerOf(tokenId), address(0));
        assertEq(address(registry.getSubregistry("test")), address(0));
    }

    function test_Revert_eject_active_name() public {
        vm.prank(address(ejectionController));
        uint64 expiry = uint64(block.timestamp) + 100;
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), IRegistry(address(registry)), MOCK_RESOLVER, expiry);

        vm.prank(address(ejectionController));
        vm.expectRevert(
            abi.encodeWithSelector(L1ETHRegistry.NameNotExpired.selector, tokenId, expiry)
        );
        registry.ejectFromNamechain(labelHash, address(1), IRegistry(address(registry)), MOCK_RESOLVER, uint64(block.timestamp) + 200);

        assertEq(registry.ownerOf(tokenId), address(this));
    }

    function test_migrateToNamechain_calls_controller() public {
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), IRegistry(address(registry)), MOCK_RESOLVER, uint64(block.timestamp) + 100);
        address l2Owner = address(0x1234);
        address l2Subregistry = address(0x5678);
        address l2Resolver = address(0x9abc);
        bytes memory data = hex"deadbeef";
        
        registry.migrateToNamechain(tokenId, l2Owner, l2Subregistry, l2Resolver, data);
        
        (uint256 lastTokenId, address lastL2Owner, address lastL2Subregistry, address lastL2Resolver, bytes memory lastData) = ejectionController.getLastMigration();
        assertEq(lastTokenId, tokenId);
        assertEq(lastL2Owner, l2Owner);
        assertEq(lastL2Subregistry, l2Subregistry);
        assertEq(lastL2Resolver, l2Resolver);
        assertEq(lastData, data);
    }

    function test_ejection_controller_sync_renewal() public {
        vm.prank(address(ejectionController));
        uint64 initialExpiry = uint64(block.timestamp) + 100;
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), IRegistry(address(registry)), MOCK_RESOLVER, initialExpiry);
        
        // Verify initial expiry
        (,uint64 storedInitialExpiry,) = datastore.getSubregistry(address(registry), tokenId);
        assertEq(storedInitialExpiry, initialExpiry, "Initial expiry not set correctly");
        
        uint64 newExpiry = uint64(block.timestamp) + 300;
        
        // Call updateExpiration via the controller
        vm.prank(address(ejectionController));
        registry.updateExpiration(tokenId, newExpiry);
        
        // Check expiry directly with correct registry address
        (,uint64 updatedExpiry,) = datastore.getSubregistry(address(registry), tokenId);
        assertEq(updatedExpiry, newExpiry, "Expiry was not updated correctly");
    }

    function test_uri() public view {
        assertEq(registry.uri(1), "");
    }

    function test_ejected_name_details() public {
        uint256 labelHash_ = uint256(keccak256("ejected"));
        address owner = address(0x1234);
        address registryAddr = address(registry);
        address resolverAddr = address(0x5678);
        uint64 expires = uint64(block.timestamp) + 500;

        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash_, owner, IRegistry(registryAddr), resolverAddr, expires);

        assertEq(registry.ownerOf(tokenId), owner, "Owner not set correctly");
        
        // Check expiry in datastore directly
        (,uint64 storedExpiry,) = datastore.getSubregistry(address(registry), tokenId);
        assertEq(storedExpiry, expires, "Expiry not set correctly");
        
        assertEq(address(registry.getSubregistry("ejected")), registryAddr, "Subregistry not set correctly");
        assertEq(registry.getResolver("ejected"), resolverAddr, "Resolver not set correctly");
    }

    function test_set_resolver() public {
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), IRegistry(address(registry)), MOCK_RESOLVER, uint64(block.timestamp) + 100);

        uint256 ROLE_SET_RESOLVER = 1 << 3;
        bytes32 resource = registry.getTokenIdResource(tokenId);
        
        registry.grantRoles(resource, ROLE_SET_RESOLVER, address(this));

        address resolverAddr = address(0x5678);
        registry.setResolver(tokenId, resolverAddr);
        
        assertEq(registry.getResolver("test"), resolverAddr);
    }

    function test_set_subregistry() public {
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), IRegistry(address(registry)), MOCK_RESOLVER, uint64(block.timestamp) + 100);

        uint256 ROLE_SET_SUBREGISTRY = 1 << 2;
        bytes32 resource = registry.getTokenIdResource(tokenId);
        
        registry.grantRoles(resource, ROLE_SET_SUBREGISTRY, address(this));

        IRegistry newSubregistry = IRegistry(address(0x1234));
        
        registry.setSubregistry(tokenId, newSubregistry);
        
        assertEq(address(registry.getSubregistry("test")), address(newSubregistry));
    }
}

contract MockEjectionController is IL1EjectionController {
    uint256 private _lastTokenId;
    address private _lastL2Owner;
    address private _lastL2Subregistry;
    address private _lastL2Resolver;
    bytes private _lastData;

    function migrateToNamechain(uint256 tokenId, address newOwner, address newSubregistry, address newResolver, bytes memory data) external override {
        _lastTokenId = tokenId;
        _lastL2Owner = newOwner;
        _lastL2Subregistry = newSubregistry;
        _lastL2Resolver = newResolver;
        _lastData = data;
    }

    function completeEjectionFromNamechain(
        uint256,
        address,
        address,
        address,
        uint64,
        bytes memory
    ) external override {}

    function syncRenewal(uint256 tokenId, uint64 newExpiry) external override {
        L1ETHRegistry(msg.sender).updateExpiration(tokenId, newExpiry);
    }
    
    function triggerSyncRenewal(L1ETHRegistry _registry, uint256 tokenId, uint64 newExpiry) external {
        _registry.updateExpiration(tokenId, newExpiry);
    }
    
    function getLastMigration() external view returns (uint256, address, address, address, bytes memory) {
        return (_lastTokenId, _lastL2Owner, _lastL2Subregistry, _lastL2Resolver, _lastData);
    }
}
