// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "../src/L1/L1ETHRegistry.sol";
import "../src/common/RegistryDatastore.sol";
import "../src/common/IRegistry.sol";
import "../src/L1/L1EjectionController.sol";
import "../src/common/IEjectionController.sol";
import {EnhancedAccessControl} from "../src/common/EnhancedAccessControl.sol";
import "../src/common/IRegistryMetadata.sol";
import {RegistryRolesMixin} from "../src/common/RegistryRolesMixin.sol";
import "../src/common/BaseRegistry.sol";
import "../src/common/IStandardRegistry.sol";
import "../src/common/ETHRegistry.sol";
import "../src/common/NameUtils.sol";

contract MockRegistryMetadata is IRegistryMetadata {
    function tokenUri(uint256) external pure override returns (string memory) {
        return "";
    }
}

contract TestL1ETHRegistry is Test, ERC1155Holder, RegistryRolesMixin, EnhancedAccessControl {
    RegistryDatastore datastore;
    L1ETHRegistry registry;
    MockL1EjectionController ejectionController;
    MockRegistryMetadata registryMetadata;
    address constant MOCK_RESOLVER = address(0xabcd);

    uint256 labelHash = uint256(keccak256("test"));

    function supportsInterface(bytes4 /*interfaceId*/) public pure override(ERC1155Holder, EnhancedAccessControl) returns (bool) {
        return true;
    }
    
    function setUp() public {
        datastore = new RegistryDatastore();
        registryMetadata = new MockRegistryMetadata();
        
        // Create a temporary controller to satisfy the ETHRegistry constructor
        MockL1EjectionController tempController = new MockL1EjectionController(IL1ETHRegistry(address(0)));
        
        // Deploy the registry with temporary controller
        registry = new L1ETHRegistry(datastore, registryMetadata, IEjectionController(address(tempController)));
        
        // Create the real controller with the correct registry
        ejectionController = new MockL1EjectionController(registry);
        
        // Update the registry to use the real controller
        registry.grantRootRoles(ROLE_SET_EJECTION_CONTROLLER, address(this));
        registry.setEjectionController(ejectionController);
    }

    function test_eject_from_namechain_unlocked() public {
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, MOCK_RESOLVER, uint64(block.timestamp) + 86400);
        
        assertEq(registry.ownerOf(tokenId), address(this));
    }

    function test_eject_from_namechain_basic() public {
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, MOCK_RESOLVER, uint64(block.timestamp) + 86400);
        
        assertEq(registry.ownerOf(tokenId), address(this));
        
        assertEq(address(registry.getSubregistry("test")), address(registry));

        assertEq(registry.getResolver("test"), MOCK_RESOLVER);
    }

    function test_eject_from_namechain_emits_events() public {
        vm.recordLogs();
        
        vm.prank(address(ejectionController));
        registry.ejectFromNamechain(labelHash, address(this), registry, MOCK_RESOLVER, uint64(block.timestamp) + 86400);

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
        registry.ejectFromNamechain(labelHash, address(this), registry, MOCK_RESOLVER, uint64(block.timestamp) + 86400);
        vm.stopPrank();
    }

    function test_Revert_eject_from_namechain_not_expired() public {
        // First register the name
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, MOCK_RESOLVER, uint64(block.timestamp) + 86400);
        
        // Try to eject again while not expired
        vm.prank(address(ejectionController));
        vm.expectRevert(abi.encodeWithSelector(L1ETHRegistry.NameNotExpired.selector, tokenId, uint64(block.timestamp) + 86400));
        registry.ejectFromNamechain(labelHash, address(this), registry, MOCK_RESOLVER, uint64(block.timestamp) + 86400);
    }

    function test_updateExpiration() public {
        vm.prank(address(ejectionController));
        uint64 expiryTime = uint64(block.timestamp) + 100;
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, MOCK_RESOLVER, expiryTime);
        
        // Verify initial expiry was set
        (,uint64 initialExpiry,) = datastore.getSubregistry(address(registry), tokenId);
        assertEq(initialExpiry, expiryTime, "Initial expiry not set correctly");
        
        uint64 newExpiry = uint64(block.timestamp) + 200;
        
        vm.prank(address(ejectionController));
        ejectionController.syncRenewal(tokenId, newExpiry);

        // Verify new expiry was set
        (,uint64 updatedExpiry,) = datastore.getSubregistry(address(registry), tokenId);
        assertEq(updatedExpiry, newExpiry, "Expiry was not updated correctly");
    }

    function test_updateExpiration_emits_event() public {
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, MOCK_RESOLVER, uint64(block.timestamp) + 100);
        
        uint64 newExpiry = uint64(block.timestamp) + 200;

        vm.recordLogs();
        
        vm.prank(address(ejectionController));
        ejectionController.syncRenewal(tokenId, newExpiry);

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
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, MOCK_RESOLVER, uint64(block.timestamp) + 100);
        
        vm.warp(block.timestamp + 101);

        vm.prank(address(ejectionController));
        vm.expectRevert(abi.encodeWithSelector(IStandardRegistry.NameExpired.selector, tokenId));
        ejectionController.syncRenewal(tokenId, uint64(block.timestamp) + 200);
    }

    function test_Revert_updateExpiration_reduce_expiry() public {
        vm.prank(address(ejectionController));
        uint64 initialExpiry = uint64(block.timestamp) + 200;
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, MOCK_RESOLVER, initialExpiry);
        
        uint64 newExpiry = uint64(block.timestamp) + 100;

        vm.prank(address(ejectionController));
        vm.expectRevert(
            abi.encodeWithSelector(
                IStandardRegistry.CannotReduceExpiration.selector, initialExpiry, newExpiry
            )
        );
        ejectionController.syncRenewal(tokenId, newExpiry);
    }

    function test_migrateToNamechain() public {
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, MOCK_RESOLVER, uint64(block.timestamp) + 86400);

        bytes memory data = hex"beef";

        vm.recordLogs();
        registry.safeTransferFrom(address(this), address(ejectionController), tokenId, 1, data);

        // Check that the token is now owned by address(0)
        assertEq(registry.ownerOf(tokenId), address(0), "Token should have no owner after migration");

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool eventReceived = false;
        for (uint256 i = 0; i < entries.length; i++) {
            bytes32 topic = entries[i].topics[0];
            if (topic == keccak256("MockNameEjectedToL2(uint256,bytes)")) {
                eventReceived = true;
                break;
            }
        }
        assertTrue(eventReceived, "MockNameEjectedToL2 event not found");
    }

    function test_ejectionController_integration() public {
        // Verify the controller is properly set
        assertEq(address(registry.ejectionController()), address(ejectionController));
        
        // Test complete ejection flow
        vm.prank(address(ejectionController));
        uint256 tokenId = registry.ejectFromNamechain(labelHash, address(this), registry, MOCK_RESOLVER, uint64(block.timestamp) + 86400);
        
        // Verify the token exists and has correct ownership
        assertEq(registry.ownerOf(tokenId), address(this));
        
        // Test the renewal from the controller
        uint64 newExpiry = uint64(block.timestamp) + 100000;
        vm.prank(address(ejectionController));
        ejectionController.syncRenewal(tokenId, newExpiry);
        
        // Verify expiry was updated
        (,uint64 updatedExpiry,) = datastore.getSubregistry(address(registry), tokenId);
        assertEq(updatedExpiry, newExpiry);
        
        // Test the migration to L2 flow
        bytes memory data = abi.encode(address(1), address(2), address(3));
        vm.recordLogs();
        registry.safeTransferFrom(address(this), address(ejectionController), tokenId, 1, data);
        
        // Verify that onERC1155Received was called and the token is relinquished
        assertEq(registry.ownerOf(tokenId), address(0), "Token should have no owner after migration");
    }

    function test_onERC1155BatchReceived() public {
        // Register multiple names to migrate to L2
        vm.startPrank(address(ejectionController));
        
        uint256 labelHash1 = uint256(keccak256("test1"));
        uint256 labelHash2 = uint256(keccak256("test2"));
        uint256 labelHash3 = uint256(keccak256("test3"));
        
        uint64 expiryTime = uint64(block.timestamp) + 86400;
        
        uint256 tokenId1 = registry.ejectFromNamechain(labelHash1, address(this), registry, MOCK_RESOLVER, expiryTime);
        uint256 tokenId2 = registry.ejectFromNamechain(labelHash2, address(this), registry, MOCK_RESOLVER, expiryTime);
        uint256 tokenId3 = registry.ejectFromNamechain(labelHash3, address(this), registry, MOCK_RESOLVER, expiryTime);
        
        vm.stopPrank();
        
        // Verify we own the tokens
        assertEq(registry.ownerOf(tokenId1), address(this));
        assertEq(registry.ownerOf(tokenId2), address(this));
        assertEq(registry.ownerOf(tokenId3), address(this));
        
        // Set up batch transfer data
        uint256[] memory ids = new uint256[](3);
        ids[0] = tokenId1;
        ids[1] = tokenId2;
        ids[2] = tokenId3;
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1;
        amounts[1] = 1;
        amounts[2] = 1;
        
        bytes memory data = hex"1234";
        
        // Execute batch transfer
        vm.recordLogs();
        registry.safeBatchTransferFrom(address(this), address(ejectionController), ids, amounts, data);
        
        // Verify all tokens were processed correctly
        for (uint256 i = 0; i < ids.length; i++) {
            assertEq(registry.ownerOf(ids[i]), address(0), "Token should have been relinquished");
        }
        
        // Check for batch event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 batchEventsCount = 0;
        
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("MockNameEjectedToL2(uint256,bytes)")) {
                batchEventsCount++;
            }
        }
        
        assertEq(batchEventsCount, 3, "Should have emitted 3 MockNameEjectedToL2 events");
    }
}

contract MockL1EjectionController is L1EjectionController {
    event MockNameEjectedToL2(uint256 tokenId, bytes data);
    
    constructor(IL1ETHRegistry _registry) L1EjectionController(_registry) {}
    
    function onRenew(uint256, uint64, address) external override {}
    
    function onRelinquish(uint256, address) external override {}
    
    function completeEjectionFromNamechain(
        uint256 tokenId,
        address l1Owner,
        address l1Subregistry,
        address l1Resolver,
        uint64 expires,
        bytes memory
    ) external {
        _completeEjectionFromL2(tokenId, l1Owner, l1Subregistry, l1Resolver, expires);
    }
    
    function syncRenewal(uint256 tokenId, uint64 newExpiry) external {
        _syncRenewal(tokenId, newExpiry);
    }
    
    /**
     * @dev Overridden to emit a mock event after calling the parent logic.
     */
    function _onEjectToL2(uint256 tokenId, bytes memory data) internal override {
        super._onEjectToL2(tokenId, data);
        emit MockNameEjectedToL2(tokenId, data);
    }
}
