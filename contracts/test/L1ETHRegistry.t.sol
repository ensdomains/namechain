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
import "../src/common/ITokenObserver.sol";

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
        registry = new L1ETHRegistry(datastore, registryMetadata, IL1EjectionController(address(ejectionController)));
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
        assertEq(keccak256(lastData), keccak256(data));
    }

    function test_migrateToNamechain_only_owner() public {
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(0xdead), IRegistry(address(registry)), MOCK_RESOLVER, uint64(block.timestamp) + 86400);

        // Try to migrate as a non-owner (the current test is run as address(this))
        vm.expectRevert(abi.encodeWithSelector(BaseRegistry.AccessDenied.selector, tokenId, address(0xdead), address(this)));
        registry.migrateToNamechain(tokenId, address(1), address(2), address(3), hex"beef");
    }

    function test_setEjectionController() public {
        // Create a new controller
        MockEjectionController newController = new MockEjectionController();
        
        // Grant necessary permissions
        registry.grantRootRoles(ROLE_SET_EJECTION_CONTROLLER, address(this));
        
        // Set new controller
        registry.setEjectionController(IEjectionController(address(newController)));
        
        // Verify the controller was set
        assertEq(address(registry.ejectionController()), address(newController));
    }

    function test_onRenew() public {
        uint256 tokenId = 123;
        uint64 expires = uint64(block.timestamp + 86400);
        address renewedBy = address(this);

        vm.recordLogs();
        registry.onRenew(tokenId, expires, renewedBy);
        
        // Verify the ejection controller was called through logs or we could mock the controller
        // Here we'd need to check if ejectionController.onRenew was called with correct params
        // This is just structural testing to ensure the function calls through correctly
    }

    function test_onRelinquish() public {
        uint256 tokenId = 123;
        address relinquishedBy = address(this);

        vm.recordLogs();
        registry.onRelinquish(tokenId, relinquishedBy);
        
        // Verify the ejection controller was called through logs or we could mock the controller
        // Here we'd need to check if ejectionController.onRelinquish was called with correct params
        // This is just structural testing to ensure the function calls through correctly
    }
}

contract MockEjectionController is IL1EjectionController {
    uint256 private _lastTokenId;
    address private _lastL2Owner;
    address private _lastL2Subregistry;
    address private _lastL2Resolver;
    bytes private _lastData;

    // Implement ITokenObserver interface
    function onRenew(uint256, uint64, address) external override {}
    function onRelinquish(uint256, address) external override {}

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
