// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

import "../src/common/RegistryDatastore.sol";
import "../src/common/IRegistry.sol";
import {L1BridgeController} from "../src/L1/L1BridgeController.sol";
import {EjectionController} from "../src/common/EjectionController.sol";
import {TransferData} from "../src/common/TransferData.sol";
import {EnhancedAccessControl, LibEACBaseRoles} from "../src/common/EnhancedAccessControl.sol";
import {IEnhancedAccessControl} from "../src/common/IEnhancedAccessControl.sol";
import "../src/common/IRegistryMetadata.sol";
import {LibRegistryRoles} from "../src/common/LibRegistryRoles.sol";
import "../src/common/BaseRegistry.sol";
import "../src/common/IStandardRegistry.sol";
import "../src/common/NameUtils.sol";
import {MockPermissionedRegistry} from "./mocks/MockPermissionedRegistry.sol";
import {IPermissionedRegistry} from "../src/common/IPermissionedRegistry.sol";
import {IBridge, LibBridgeRoles} from "../src/common/IBridge.sol";

contract MockRegistryMetadata is IRegistryMetadata {
    function tokenUri(uint256) external pure override returns (string memory) {
        return "";
    }
}

contract MockBridge is IBridge {
    function sendMessage(bytes memory) external override {}
}

contract TestL1BridgeController is Test, ERC1155Holder, EnhancedAccessControl {
    RegistryDatastore datastore;
    MockPermissionedRegistry registry;
    L1BridgeController bridgeController;
    MockRegistryMetadata registryMetadata;
    MockBridge bridge;
    address constant MOCK_RESOLVER = address(0xabcd);
    address user = address(0x1234);

    uint256 labelHash = uint256(keccak256("test"));
    string testLabel = "test";

    function supportsInterface(bytes4 /*interfaceId*/) public pure override(ERC1155Holder, EnhancedAccessControl) returns (bool) {
        return true;
    }

    /**
     * Helper method to create properly encoded data for the ERC1155 transfers
     */
    function _createEjectionData(
        address l2Owner,
        address l2Subregistry,
        address l2Resolver,
        uint64 expiryTime,
        uint256 roleBitmap
    ) internal view returns (bytes memory) {
        TransferData memory transferData = TransferData({
            label: testLabel,
            owner: l2Owner,
            subregistry: l2Subregistry,
            resolver: l2Resolver,
            expires: expiryTime,
            roleBitmap: roleBitmap
        });
        return abi.encode(transferData);
    }
    
    /**
     * Helper method to create properly encoded data for the ERC1155 transfers with custom label
     */
    function _createEjectionDataWithLabel(
        string memory label,
        address l2Owner,
        address l2Subregistry,
        address l2Resolver,
        uint64 expiryTime,
        uint256 roleBitmap
    ) internal pure returns (bytes memory) {
        TransferData memory transferData = TransferData({
            label: label,
            owner: l2Owner,
            subregistry: l2Subregistry,
            resolver: l2Resolver,
            expires: expiryTime,
            roleBitmap: roleBitmap
        });
        return abi.encode(transferData);
    }
    
    /**
     * Helper method to create properly encoded batch data for the ERC1155 batch transfers
     */
    function _createBatchEjectionData(
        address[] memory l2Owners,
        address[] memory l2Subregistries,
        address[] memory l2Resolvers,
        uint64[] memory expiryTimes,
        uint256[] memory roleBitmaps
    ) internal pure returns (bytes memory) {
        require(l2Owners.length == l2Subregistries.length && 
                l2Owners.length == l2Resolvers.length && 
                l2Owners.length == expiryTimes.length &&
                l2Owners.length == roleBitmaps.length, 
                "Array lengths must match");
                
        TransferData[] memory transferDataArray = new TransferData[](l2Owners.length);
        
        string[3] memory labels = ["test1", "test2", "test3"];
        
        for (uint256 i = 0; i < l2Owners.length; i++) {
            transferDataArray[i] = TransferData({
                label: labels[i],
                owner: l2Owners[i],
                subregistry: l2Subregistries[i],
                resolver: l2Resolvers[i],
                expires: expiryTimes[i],
                roleBitmap: roleBitmaps[i]
            });
        }
        
        return abi.encode(transferDataArray);
    }
    
    function setUp() public {
        datastore = new RegistryDatastore();
        registryMetadata = new MockRegistryMetadata();
        bridge = new MockBridge();
        
        // Deploy the registry
        registry = new MockPermissionedRegistry(datastore, registryMetadata, address(this), LibEACBaseRoles.ALL_ROLES);
        
        // Create the real controller with the correct registry and bridge
        bridgeController = new L1BridgeController(registry, bridge);

        // grant roles to registry operations
        registry.grantRootRoles(LibRegistryRoles.ROLE_REGISTRAR | LibRegistryRoles.ROLE_RENEW, address(this));
        registry.grantRootRoles(LibRegistryRoles.ROLE_REGISTRAR | LibRegistryRoles.ROLE_RENEW | LibRegistryRoles.ROLE_BURN, address(bridgeController));
        
        // Grant bridge roles to the bridge mock so it can call the bridge controller
        bridgeController.grantRootRoles(LibBridgeRoles.ROLE_EJECTOR, address(bridge));
    }

    function test_eject_from_namechain_unlocked() public {
        uint64 expiryTime = uint64(block.timestamp) + 86400;
        TransferData memory transferData = TransferData({
            label: testLabel,
            owner: address(this),
            subregistry: address(registry),
            resolver: MOCK_RESOLVER,
            expires: expiryTime,
            roleBitmap: LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY
        });
        // Call through the bridge (using vm.prank to simulate bridge calling)
        vm.prank(address(bridge));
        bridgeController.completeEjectionFromL2(transferData);
        
        (uint256 tokenId,,) = registry.getNameData(testLabel);
        assertEq(registry.ownerOf(tokenId), address(this));
    }

    function test_eject_from_namechain_basic() public {
        uint64 expiryTime = uint64(block.timestamp) + 86400;
        uint256 expectedRoles = LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY;
        address subregistry = address(0x1234);
        TransferData memory transferData = TransferData({
            label: testLabel,
            owner: user,
            subregistry: subregistry,
            resolver: MOCK_RESOLVER,
            expires: expiryTime,
            roleBitmap: expectedRoles
        });
        // Call through the bridge (using vm.prank to simulate bridge calling)
        vm.prank(address(bridge));
        bridgeController.completeEjectionFromL2(transferData);
        
        (uint256 tokenId,,) = registry.getNameData(testLabel);
        assertEq(registry.ownerOf(tokenId), user);
        
        assertEq(address(registry.getSubregistry(testLabel)), subregistry);

        assertEq(registry.getResolver(testLabel), MOCK_RESOLVER);
        
        uint256 resource = registry.testGetResourceFromTokenId(tokenId);
        assertTrue(registry.hasRoles(resource, expectedRoles, user), "Role bitmap should match the expected roles");
    }

    function test_eject_from_namechain_emits_events() public {
        vm.recordLogs();
        
        uint64 expiryTime = uint64(block.timestamp) + 86400;
        TransferData memory transferData = TransferData({
            label: testLabel,
            owner: address(this),
            subregistry: address(registry),
            resolver: MOCK_RESOLVER,
            expires: expiryTime,
            roleBitmap: LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY
        });
        // Call through the bridge (using vm.prank to simulate bridge calling)
        vm.prank(address(bridge));
        bridgeController.completeEjectionFromL2(transferData);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundNewSubname = false;
        bool foundNameEjectedToL1 = false;
        
        bytes32 newSubnameSig = keccak256("NewSubname(uint256,string)");
        bytes32 ejectedSig = keccak256("NameEjectedToL1(bytes,uint256)");
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == newSubnameSig) {
                foundNewSubname = true;
            }
            if (entries[i].topics[0] == ejectedSig) {
                foundNameEjectedToL1 = true;
            }
        }
        
        assertTrue(foundNewSubname, "NewSubname event not found");
        assertTrue(foundNameEjectedToL1, "NameEjectedToL1 event not found");
    }

    function test_Revert_eject_from_namechain_not_expired() public {
        // First register the name
        uint64 expiryTime = uint64(block.timestamp) + 86400;
        TransferData memory transferData = TransferData({
            label: testLabel,
            owner: address(this),
            subregistry: address(registry),
            resolver: MOCK_RESOLVER,
            expires: expiryTime,
            roleBitmap: LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY
        });
        // Call through the bridge (using vm.prank to simulate bridge calling)
        vm.prank(address(bridge));
        bridgeController.completeEjectionFromL2(transferData);
        
        // Try to eject again while not expired
        vm.expectRevert(abi.encodeWithSelector(IStandardRegistry.NameAlreadyRegistered.selector, testLabel));
        vm.prank(address(bridge));
        bridgeController.completeEjectionFromL2(transferData);
    }

    function test_updateExpiration() public {
        uint64 expiryTime = uint64(block.timestamp) + 100;
        TransferData memory transferData = TransferData({
            label: testLabel,
            owner: address(this),
            subregistry: address(registry),
            resolver: MOCK_RESOLVER,
            expires: expiryTime,
            roleBitmap: LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY
        });
        // Call through the bridge (using vm.prank to simulate bridge calling)
        vm.prank(address(bridge));
        bridgeController.completeEjectionFromL2(transferData);
        
        (uint256 tokenId,,) = registry.getNameData(testLabel);
        
        // Verify initial expiry was set
        (,uint64 initialExpiry,) = datastore.getSubregistry(address(registry), tokenId);
        assertEq(initialExpiry, expiryTime, "Initial expiry not set correctly");
        
        uint64 newExpiry = uint64(block.timestamp) + 200;
        
        vm.prank(address(bridge));
        bridgeController.syncRenewal(tokenId, newExpiry);

        // Verify new expiry was set
        (,uint64 updatedExpiry,) = datastore.getSubregistry(address(registry), tokenId);
        assertEq(updatedExpiry, newExpiry, "Expiry was not updated correctly");
    }

    function test_updateExpiration_emits_event() public {
        uint64 expiryTime = uint64(block.timestamp) + 100;
        TransferData memory transferData = TransferData({
            label: testLabel,
            owner: address(this),
            subregistry: address(registry),
            resolver: MOCK_RESOLVER,
            expires: expiryTime,
            roleBitmap: LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY
        });
        // Call through the bridge (using vm.prank to simulate bridge calling)
        vm.prank(address(bridge));
        bridgeController.completeEjectionFromL2(transferData);
        
        (uint256 tokenId,,) = registry.getNameData(testLabel);
        
        uint64 newExpiry = uint64(block.timestamp) + 200;

        vm.recordLogs();
        
        vm.prank(address(bridge));
        bridgeController.syncRenewal(tokenId, newExpiry);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundNameRenewed = false;
        bool foundRenewalSynchronized = false;
        bytes32 nameRenewedSig = keccak256("NameRenewed(uint256,uint64,address)");
        bytes32 renewalSynchronizedSig = keccak256("RenewalSynchronized(uint256,uint64)");
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == nameRenewedSig) {
                foundNameRenewed = true;
            }
            if (entries[i].topics[0] == renewalSynchronizedSig) {
                foundRenewalSynchronized = true;
            }
        }
        assertTrue(foundNameRenewed, "NameRenewed event not found");
        assertTrue(foundRenewalSynchronized, "RenewalSynchronized event not found");
    }

    function test_Revert_updateExpiration_expired_name() public {
        uint64 expiryTime = uint64(block.timestamp) + 100;
        TransferData memory transferData = TransferData({
            label: testLabel,
            owner: address(this),
            subregistry: address(registry),
            resolver: MOCK_RESOLVER,
            expires: expiryTime,
            roleBitmap: LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY
        });
        // Call through the bridge (using vm.prank to simulate bridge calling)
        vm.prank(address(bridge));
        bridgeController.completeEjectionFromL2(transferData);
        
        (uint256 tokenId,,) = registry.getNameData(testLabel);
        
        vm.warp(block.timestamp + 101);

        vm.expectRevert(abi.encodeWithSelector(IStandardRegistry.NameExpired.selector, tokenId));
        vm.prank(address(bridge));
        bridgeController.syncRenewal(tokenId, uint64(block.timestamp) + 200);
    }

    function test_Revert_updateExpiration_reduce_expiry() public {
        uint64 initialExpiry = uint64(block.timestamp) + 200;
        TransferData memory transferData = TransferData({
            label: testLabel,
            owner: address(this),
            subregistry: address(registry),
            resolver: MOCK_RESOLVER,
            expires: initialExpiry,
            roleBitmap: LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY
        });
        // Call through the bridge (using vm.prank to simulate bridge calling)
        vm.prank(address(bridge));
        bridgeController.completeEjectionFromL2(transferData);
        
        (uint256 tokenId,,) = registry.getNameData(testLabel);
        
        uint64 newExpiry = uint64(block.timestamp) + 100;

        vm.expectRevert(
            abi.encodeWithSelector(
                IStandardRegistry.CannotReduceExpiration.selector, initialExpiry, newExpiry
            )
        );
        vm.prank(address(bridge));
        bridgeController.syncRenewal(tokenId, newExpiry);
    }

    function test_ejectToNamechain() public {
        uint64 expiryTime = uint64(block.timestamp) + 86400;
        uint256 roleBitmap = LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY;
        
        // Register the name directly using the registry
        registry.register(testLabel, address(this), registry, MOCK_RESOLVER, roleBitmap, expiryTime);

        (uint256 tokenId,,) = registry.getNameData(testLabel);

        // Setup ejection data
        address expectedOwner = address(1);
        address expectedSubregistry = address(2);
        address expectedResolver = address(3);
        uint64 expectedExpiry = uint64(block.timestamp + 86400);
        uint256 expectedRoleBitmap = LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY;
        
        bytes memory data = _createEjectionData(
            expectedOwner, 
            expectedSubregistry, 
            expectedResolver, 
            expectedExpiry,
            expectedRoleBitmap
        );

        vm.recordLogs();
        registry.safeTransferFrom(address(this), address(bridgeController), tokenId, 1, data);

        // Check that the token is now owned by address(0)
        assertEq(registry.ownerOf(tokenId), address(0), "Token should have no owner after ejection");

        _verifyEjectionEvent(expectedOwner, expectedSubregistry, expectedResolver, expectedExpiry);
    }
    
    function _verifyEjectionEvent(address /* expectedOwner */, address /* expectedSubregistry */, address /* expectedResolver */, uint64 /* expectedExpiry */) internal {
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool eventReceived = false;
        bytes32 expectedSig = keccak256("NameEjectedToL2(bytes,uint256)");
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == expectedSig) {
                eventReceived = true;
                break;
            }
        }
        assertTrue(eventReceived, "NameEjectedToL2 event not found");
    }

    function test_Revert_ejectToNamechain_invalid_label() public {
        uint64 expiryTime = uint64(block.timestamp) + 86400;
        uint256 roleBitmap = LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY;
        
        // Register the name directly using the registry
        registry.register(testLabel, address(this), registry, MOCK_RESOLVER, roleBitmap, expiryTime);

        (uint256 tokenId,,) = registry.getNameData(testLabel);

        // Setup ejection data with invalid label
        string memory invalidLabel = "invalid";
        address expectedOwner = address(1);
        address expectedSubregistry = address(2);
        address expectedResolver = address(3);
        uint64 expectedExpiry = uint64(block.timestamp + 86400);
        uint256 expectedRoleBitmap = LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY;
        
        bytes memory data = _createEjectionDataWithLabel(
            invalidLabel,
            expectedOwner, 
            expectedSubregistry, 
            expectedResolver, 
            expectedExpiry,
            expectedRoleBitmap
        );

        // Transfer should revert due to invalid label
        vm.expectRevert(abi.encodeWithSelector(EjectionController.InvalidLabel.selector, tokenId, invalidLabel));
        registry.safeTransferFrom(address(this), address(bridgeController), tokenId, 1, data);
    }

    function test_Revert_ejectToL2_null_owner() public {
        uint64 expiryTime = uint64(block.timestamp) + 86400;
        uint256 roleBitmap = LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY;
        
        // Register the name directly using the registry
        registry.register(testLabel, address(this), registry, MOCK_RESOLVER, roleBitmap, expiryTime);

        (uint256 tokenId,,) = registry.getNameData(testLabel);

        // Setup ejection data with null owner
        address nullOwner = address(0);
        address expectedSubregistry = address(2);
        address expectedResolver = address(3);
        uint64 expectedExpiry = uint64(block.timestamp + 86400);
        uint256 expectedRoleBitmap = LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY;
        
        bytes memory data = _createEjectionData(
            nullOwner, 
            expectedSubregistry, 
            expectedResolver, 
            expectedExpiry,
            expectedRoleBitmap
        );

        // Transfer should revert due to null owner
        vm.expectRevert(abi.encodeWithSelector(L1BridgeController.InvalidOwner.selector));
        registry.safeTransferFrom(address(this), address(bridgeController), tokenId, 1, data);
    }

    
    function test_onERC1155BatchReceived() public {
        (uint256[] memory ids, uint256[] memory amounts, bytes memory data) = _setupBatchTransferTest();
        
        // Execute batch transfer
        vm.recordLogs();
        registry.safeBatchTransferFrom(address(this), address(bridgeController), ids, amounts, data);
        
        // Verify all tokens were processed correctly
        for (uint256 i = 0; i < ids.length; i++) {
            assertEq(registry.ownerOf(ids[i]), address(0), "Token should have been burned");
        }
        
        _verifyBatchEventEmission();
    }
    
    function _setupBatchTransferTest() internal returns (uint256[] memory ids, uint256[] memory amounts, bytes memory data) {
        uint64 expiryTime = uint64(block.timestamp) + 86400;
        
        // Register names
        registry.register("test1", address(this), registry, MOCK_RESOLVER, LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY, expiryTime);
        registry.register("test2", address(this), registry, MOCK_RESOLVER, LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY, expiryTime);
        registry.register("test3", address(this), registry, MOCK_RESOLVER, LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY, expiryTime);
        
        // Get token IDs and verify ownership
        (uint256 tokenId1,,) = registry.getNameData("test1");
        (uint256 tokenId2,,) = registry.getNameData("test2");
        (uint256 tokenId3,,) = registry.getNameData("test3");
        
        assertEq(registry.ownerOf(tokenId1), address(this));
        assertEq(registry.ownerOf(tokenId2), address(this));
        assertEq(registry.ownerOf(tokenId3), address(this));
        
        // Setup arrays
        ids = new uint256[](3);
        ids[0] = tokenId1;
        ids[1] = tokenId2;
        ids[2] = tokenId3;
        
        amounts = new uint256[](3);
        amounts[0] = 1;
        amounts[1] = 1;
        amounts[2] = 1;
        
        data = _createBatchTransferData();
    }
    
    function _createBatchTransferData() internal view returns (bytes memory) {
        address[] memory owners = new address[](3);
        address[] memory subregistries = new address[](3);
        address[] memory resolvers = new address[](3);
        uint64[] memory expiries = new uint64[](3);
        uint256[] memory roleBitmaps = new uint256[](3);
        
        for (uint256 i = 0; i < 3; i++) {
            owners[i] = address(uint160(i + 1));
            subregistries[i] = address(uint160(i + 10));
            resolvers[i] = address(uint160(i + 100));
            expiries[i] = uint64(block.timestamp + 86400 * (i + 1));
            roleBitmaps[i] = LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY | (i * 2);
        }
        
        return _createBatchEjectionData(owners, subregistries, resolvers, expiries, roleBitmaps);
    }
    
    function _verifyBatchEventEmission() internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 batchEventsCount = 0;
        bytes32 expectedSig = keccak256("NameEjectedToL2(bytes,uint256)");
        
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == expectedSig) {
                batchEventsCount++;
            }
        }
        
        assertEq(batchEventsCount, 3, "Should have emitted 3 NameEjectedToL2 events");
    }

    function test_Revert_onERC1155BatchReceived_invalid_label() public {
        uint64 expiryTime = uint64(block.timestamp) + 86400;
        
        // Register names
        registry.register("test1", address(this), registry, MOCK_RESOLVER, LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY, expiryTime);
        registry.register("test2", address(this), registry, MOCK_RESOLVER, LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY, expiryTime);
        
        // Get token IDs
        (uint256 tokenId1,,) = registry.getNameData("test1");
        (uint256 tokenId2,,) = registry.getNameData("test2");
        
        // Setup arrays with one invalid label
        uint256[] memory ids = new uint256[](2);
        ids[0] = tokenId1;
        ids[1] = tokenId2;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;
        
        // Create batch data with one invalid label
        string[] memory labels = new string[](2);
        labels[0] = "test1";      // valid
        labels[1] = "invalid";    // invalid for tokenId2
        
        address[] memory owners = new address[](2);
        address[] memory subregistries = new address[](2);
        address[] memory resolvers = new address[](2);
        uint64[] memory expiries = new uint64[](2);
        uint256[] memory roleBitmaps = new uint256[](2);
        
        for (uint256 i = 0; i < 2; i++) {
            owners[i] = address(uint160(i + 1));
            subregistries[i] = address(uint160(i + 10));
            resolvers[i] = address(uint160(i + 100));
            expiries[i] = uint64(block.timestamp + 86400);
            roleBitmaps[i] = LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY;
        }
        
        bytes memory data = _createBatchEjectionDataWithLabels(labels, owners, subregistries, resolvers, expiries, roleBitmaps);
        
        // Should revert due to invalid label for tokenId2
        vm.expectRevert(abi.encodeWithSelector(EjectionController.InvalidLabel.selector, tokenId2, "invalid"));
        registry.safeBatchTransferFrom(address(this), address(bridgeController), ids, amounts, data);
    }
    
    /**
     * Helper method to create properly encoded batch data for the ERC1155 batch transfers with custom labels
     */
    function _createBatchEjectionDataWithLabels(
        string[] memory labels,
        address[] memory l2Owners,
        address[] memory l2Subregistries,
        address[] memory l2Resolvers,
        uint64[] memory expiryTimes,
        uint256[] memory roleBitmaps
    ) internal pure returns (bytes memory) {
        require(labels.length == l2Owners.length && 
                l2Owners.length == l2Subregistries.length && 
                l2Owners.length == l2Resolvers.length && 
                l2Owners.length == expiryTimes.length &&
                l2Owners.length == roleBitmaps.length, 
                "Array lengths must match");
                
        TransferData[] memory transferDataArray = new TransferData[](l2Owners.length);
        
        for (uint256 i = 0; i < l2Owners.length; i++) {
            transferDataArray[i] = TransferData({
                label: labels[i],
                owner: l2Owners[i],
                subregistry: l2Subregistries[i],
                resolver: l2Resolvers[i],
                expires: expiryTimes[i],
                roleBitmap: roleBitmaps[i]
            });
        }
        
        return abi.encode(transferDataArray);
    }

    function test_Revert_completeEjectionFromL2_not_bridge() public {
        uint64 expiryTime = uint64(block.timestamp) + 86400;
        TransferData memory transferData = TransferData({
            label: testLabel,
            owner: address(this),
            subregistry: address(registry),
            resolver: MOCK_RESOLVER,
            expires: expiryTime,
            roleBitmap: LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY
        });
        
        // Try to call completeEjectionFromL2 directly (without proper role)
        vm.expectRevert(abi.encodeWithSelector(
            IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
            0, // ROOT_RESOURCE
            LibBridgeRoles.ROLE_EJECTOR,
            address(this)
        ));
        bridgeController.completeEjectionFromL2(transferData);
    }

    function test_Revert_syncRenewal_not_bridge() public {
        uint64 expiryTime = uint64(block.timestamp) + 86400;
        TransferData memory transferData = TransferData({
            label: testLabel,
            owner: address(this),
            subregistry: address(registry),
            resolver: MOCK_RESOLVER,
            expires: expiryTime,
            roleBitmap: LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY
        });
        
        // First create a name to renew
        vm.prank(address(bridge));
        bridgeController.completeEjectionFromL2(transferData);
        
        (uint256 tokenId,,) = registry.getNameData(testLabel);
        
        // Try to call syncRenewal directly (without proper role)
        vm.expectRevert(abi.encodeWithSelector(
            IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
            0, // ROOT_RESOURCE
            LibBridgeRoles.ROLE_EJECTOR,
            address(this)
        ));
        bridgeController.syncRenewal(tokenId, uint64(block.timestamp + 86400 * 2));
    }
}


