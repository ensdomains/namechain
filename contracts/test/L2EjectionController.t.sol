// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

import {L2EjectionController} from "../src/L2/L2EjectionController.sol";
import "../src/common/PermissionedRegistry.sol";
import "../src/common/IRegistry.sol";
import "../src/common/ITokenObserver.sol";
import "../src/common/RegistryDatastore.sol";
import "../src/common/IRegistryDatastore.sol";
import "../src/common/IRegistryMetadata.sol";
import "../src/common/NameUtils.sol";
import {RegistryRolesMixin} from "../src/common/RegistryRolesMixin.sol";
import {EnhancedAccessControl} from "../src/common/EnhancedAccessControl.sol";
import {EjectionController} from "../src/common/EjectionController.sol";
import {TransferData} from "../src/common/TransferData.sol";

// Mock implementation of IRegistryMetadata
contract MockRegistryMetadata is IRegistryMetadata {
    function tokenUri(uint256) external pure override returns (string memory) {
        return "";
    }
}


contract TestL2EjectionController is Test, ERC1155Holder, RegistryRolesMixin {
    // Import constants from RegistryRolesMixin and EnhancedAccessControl
    bytes32 constant ROOT_RESOURCE = bytes32(0);
    uint256 constant ALL_ROLES = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    
    MockL2EjectionController controller; // Changed type to MockL2EjectionController
    PermissionedRegistry registry;
    RegistryDatastore datastore;
    MockRegistryMetadata registryMetadata;

    address user = address(0x1);
    address l1Owner = address(0x2);
    address l1Subregistry = address(0x3);
    address l1Resolver = address(0x6);
    address l2Owner = address(0x4);
    address l2Subregistry = address(0x5);
    address l2Resolver = address(0x7);
    
    string label = "test";
    uint256 labelHash;
    uint256 tokenId;
    uint64 expiryDuration = 86400; // 1 day
    
    /**
     * Helper method to create properly encoded data for the ERC1155 transfers
     */
    function _createEjectionData(
        string memory nameLabel,
        address owner,
        address subregistry,
        address resolver,
        uint64 expiryTime,
        uint256 roleBitmap
    ) internal pure returns (bytes memory) {
        TransferData memory transferData = TransferData({
            label: nameLabel,
            owner: owner,
            subregistry: subregistry,
            resolver: resolver,
            expires: expiryTime,
            roleBitmap: roleBitmap
        });
        return abi.encode(transferData);
    }
    
    /**
     * Helper method to create properly encoded batch data for the ERC1155 batch transfers
     */
    function _createBatchEjectionData(
        string[] memory labels,
        address[] memory owners,
        address[] memory subregistries,
        address[] memory resolvers,
        uint64[] memory expiryTimes,
        uint256[] memory roleBitmaps
    ) internal pure returns (bytes memory) {
        require(labels.length == owners.length && 
                labels.length == subregistries.length && 
                labels.length == resolvers.length && 
                labels.length == expiryTimes.length &&
                labels.length == roleBitmaps.length, 
                "Array lengths must match");
                
        TransferData[] memory transferDataArray = new TransferData[](labels.length);
        
        for (uint256 i = 0; i < labels.length; i++) {
            transferDataArray[i] = TransferData({
                label: labels[i],
                owner: owners[i],
                subregistry: subregistries[i],
                resolver: resolvers[i],
                expires: expiryTimes[i],
                roleBitmap: roleBitmaps[i]
            });
        }
        
        return abi.encode(transferDataArray);
    }

    function setUp() public {
        datastore = new RegistryDatastore();
        registryMetadata = new MockRegistryMetadata();
        
        registry = new PermissionedRegistry(datastore, registryMetadata, ALL_ROLES);
        
        // Now deploy the real mock controller with the correct registry
        controller = new MockL2EjectionController(registry); // Deploy MockL2EjectionController
        
        // Set up for testing
        labelHash = NameUtils.labelToCanonicalId(label);
        
        // Grant roles
        registry.grantRootRoles(ROLE_REGISTRAR | ROLE_RENEW, address(this));
        
        // Register a test name
        uint64 expires = uint64(block.timestamp + expiryDuration);
        tokenId = registry.register(label, user, registry, address(0), ALL_ROLES, expires);
    }

    function test_constructor() public view {
        assertEq(address(controller.registry()), address(registry));
    }

    function test_eject_flow_via_transfer() public {
        // Prepare the data for ejection with label and expiry
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint256 roleBitmap = ALL_ROLES;
        bytes memory ejectionData = _createEjectionData(label, l1Owner, l1Subregistry, l1Resolver, expiryTime, roleBitmap);
        
        // Make sure user still owns the token
        assertEq(registry.ownerOf(tokenId), user);
        
        // User transfers the token to the ejection controller
        vm.recordLogs();
        vm.prank(user);
        registry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);
        
        // Check for MockNameEjectedToL1 event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        
        bytes32 eventSig = keccak256("MockNameEjectedToL1(uint256,bytes)");
        
        for (uint i = 0; i < logs.length; i++) {
            // Check if this log is our event (emitter and first topic match)
            if (logs[i].emitter == address(controller) && 
                logs[i].topics[0] == eventSig) {
                
                // For indexed parameters, check that the topics match
                if (logs[i].topics.length > 1) {
                    assertEq(uint256(logs[i].topics[1]), tokenId);
                }
                
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "MockNameEjectedToL1 event not found");
        
        // Verify subregistry is cleared after ejection
        (address subregAddr, , ) = datastore.getSubregistry(tokenId);
        assertEq(subregAddr, address(0), "Subregistry not cleared after ejection");
        
        // Verify token observer is set
        assertEq(address(registry.tokenObservers(tokenId)), address(controller), "Token observer not set");
        
        // Verify token is now owned by the controller
        assertEq(registry.ownerOf(tokenId), address(controller), "Token should be owned by the controller");
    }

    function test_completeMigrationFromL1() public {
        // Use specific roles instead of ALL_ROLES
        uint256 originalRoles = ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY | ROLE_SET_TOKEN_OBSERVER;
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);

        string memory label2 = "test2";
        tokenId = registry.register(label2, user, registry, address(0), originalRoles, expiryTime);        
        
        // First eject the name so the controller owns it
        bytes memory ejectionData = _createEjectionData(label2, l1Owner, l1Subregistry, l1Resolver, expiryTime, originalRoles);
        vm.prank(user);
        registry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);
        
        // Verify controller owns the token
        assertEq(registry.ownerOf(tokenId), address(controller), "Controller should own the token");
        
        // Try to migrate with different roles than the original ones - these should be ignored
        uint256 differentRoles = ROLE_RENEW | ROLE_REGISTRAR;
        vm.recordLogs();
        controller.call_completeMigrationFromL1(tokenId, l2Owner, l2Subregistry, l2Resolver, differentRoles);
        
        // Verify migration results
        _verifyMigrationResults(tokenId, label2, originalRoles, differentRoles);
        _verifyMigrationEvent(tokenId, differentRoles);
    }
    
    // Helper function to verify migration results
    function _verifyMigrationResults(uint256 _tokenId, string memory _label, uint256 originalRoles, uint256 ignoredRoles) internal view {
        // Verify name was migrated - check ownership transfer
        assertEq(registry.ownerOf(_tokenId), l2Owner, "L2 owner should now own the token");
        
        // Verify subregistry and resolver were set correctly
        IRegistry subregAddr = registry.getSubregistry(_label);
        assertEq(address(subregAddr), l2Subregistry, "Subregistry not set correctly after migration");
        
        address resolverAddr = registry.getResolver(_label);
        assertEq(resolverAddr, l2Resolver, "Resolver not set correctly after migration");
        
        // ROLE BITMAP VERIFICATION:
        bytes32 resource = registry.getTokenIdResource(_tokenId);
        assertTrue(registry.hasRoles(resource, originalRoles, l2Owner), "L2 owner should have original roles");
        assertFalse(registry.hasRoles(resource, ignoredRoles, l2Owner), "L2 owner should not have new roles");
    }
    
    // Helper function to check for event emission
    function _verifyMigrationEvent(uint256 _tokenId, uint256 expectedRoleBitmap) internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        
        bytes32 eventSig = keccak256("MockNameMigratedFromL1(uint256,address,address,address,uint256)");
        
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(controller) && 
                logs[i].topics[0] == eventSig &&
                logs[i].topics.length > 1 &&
                uint256(logs[i].topics[1]) == _tokenId) {
                
                foundEvent = true;
                
                // Only decode data if there is data to decode
                if (logs[i].data.length > 0) {
                    (address emittedL2Owner, address emittedL2Subregistry, address emittedL2Resolver, uint256 emittedRoleBitmap) = 
                        abi.decode(logs[i].data, (address, address, address, uint256));
                    
                    // Verify all data fields match expected values
                    assertEq(emittedL2Owner, l2Owner);
                    assertEq(emittedL2Subregistry, l2Subregistry);
                    assertEq(emittedL2Resolver, l2Resolver);
                    assertEq(emittedRoleBitmap, expectedRoleBitmap);
                }
                break;
            }
        }
        
        assertTrue(foundEvent, "MockNameMigratedFromL1 event not found");
    }

    function test_Revert_completeMigrationFromL1_notOwner() public {
        // Expect revert with NotTokenOwner error from the L2EjectionController logic
        vm.expectRevert(abi.encodeWithSelector(L2EjectionController.NotTokenOwner.selector, tokenId));
        // Call the public wrapper which invokes the internal logic that should revert
        controller.call_completeMigrationFromL1(tokenId, l2Owner, l2Subregistry, l2Resolver, ALL_ROLES);
    }

    function test_supportsInterface() public view {
        assertTrue(controller.supportsInterface(type(EjectionController).interfaceId));
        assertTrue(controller.supportsInterface(type(IERC1155Receiver).interfaceId));
        assertTrue(controller.supportsInterface(type(ITokenObserver).interfaceId));
        assertFalse(controller.supportsInterface(0x12345678));
    }

    function test_onERC1155BatchReceived() public {
        // Register two more names
        uint64 expires = uint64(block.timestamp + expiryDuration);
        string memory label2 = "test2";
        string memory label3 = "test3";
        uint256 tokenId2 = registry.register(label2, user, registry, address(0), ALL_ROLES, expires);
        uint256 tokenId3 = registry.register(label3, user, registry, address(0), ALL_ROLES, expires);
        
        // Create batch of tokens to transfer
        uint256[] memory ids = new uint256[](2);
        ids[0] = tokenId2;
        ids[1] = tokenId3;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;
        
        // Create arrays for transfer data
        string[] memory labels = new string[](2);
        address[] memory owners = new address[](2);
        address[] memory subregistries = new address[](2);
        address[] memory resolvers = new address[](2);
        uint64[] memory expiries = new uint64[](2);
        uint256[] memory roleBitmaps = new uint256[](2);
        
        // Set values for each token
        labels[0] = label2;
        labels[1] = label3;
        
        for (uint256 i = 0; i < 2; i++) {
            owners[i] = l1Owner;
            subregistries[i] = l1Subregistry;
            resolvers[i] = l1Resolver;
            expiries[i] = uint64(block.timestamp + expiryDuration);
            roleBitmaps[i] = ALL_ROLES - i; // Different role for each token
        }
        
        // Create batch ejection data
        bytes memory batchData = _createBatchEjectionData(labels, owners, subregistries, resolvers, expiries, roleBitmaps);
        
        // Execute batch transfer
        vm.startPrank(user);
        vm.recordLogs();
        registry.safeBatchTransferFrom(user, address(controller), ids, amounts, batchData);
        vm.stopPrank();
        
        // Verify tokens are now owned by the controller
        assertEq(registry.ownerOf(ids[0]), address(controller), "First token should be owned by controller");
        assertEq(registry.ownerOf(ids[1]), address(controller), "Second token should be owned by controller");
        
        // Verify subregistry was cleared for both tokens
        (address subregAddr, , ) = datastore.getSubregistry(ids[0]);
        assertEq(subregAddr, address(0), "Subregistry not cleared for token 1");
        (subregAddr, , ) = datastore.getSubregistry(ids[1]);
        assertEq(subregAddr, address(0), "Subregistry not cleared for token 2");
        
        // Verify token observer was set for both tokens
        assertEq(address(registry.tokenObservers(ids[0])), address(controller), "Token observer not set for token 1");
        assertEq(address(registry.tokenObservers(ids[1])), address(controller), "Token observer not set for token 2");
        
        // Check for events
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 ejectionEventsCount = 0;
        bytes32 expectedSig = keccak256("MockNameEjectedToL1(uint256,bytes)");
        
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(controller) && 
                logs[i].topics[0] == expectedSig) {
                ejectionEventsCount++;
            }
        }
        
        assertEq(ejectionEventsCount, 2, "Should have emitted 2 MockNameEjectedToL1 events");
    }

    function test_onRenew_emitsEvent() public {
        // First eject the name so the controller owns it and becomes the observer
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint32 roleBitmap = uint32(ALL_ROLES);
        bytes memory ejectionData = _createEjectionData(label, l1Owner, l1Subregistry, l1Resolver, expiryTime, roleBitmap);
        vm.prank(user);
        registry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);
        
        // Verify controller owns the token and is the observer
        assertEq(registry.ownerOf(tokenId), address(controller), "Controller should own the token");
        assertEq(address(registry.tokenObservers(tokenId)), address(controller), "Controller should be the observer");
        
        uint64 newExpiry = uint64(block.timestamp + expiryDuration * 2);
        address renewer = address(this);
        
        // Call onRenew directly on the controller (simulating a call from the registry)
        vm.recordLogs();
        controller.onRenew(tokenId, newExpiry, renewer);
        
        // Check for MockNameRenewed event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        
        bytes32 eventSig = keccak256("MockNameRenewed(uint256,uint64,address)");
        
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(controller) && 
                logs[i].topics[0] == eventSig) {
                
                // For indexed parameters, check that the topics match
                if (logs[i].topics.length > 1) {
                    assertEq(uint256(logs[i].topics[1]), tokenId, "Event tokenId should match");
                }
                
                // Only decode data if there is data to decode
                if (logs[i].data.length > 0) {
                    (uint64 emittedExpiry, address emittedRenewer) = 
                        abi.decode(logs[i].data, (uint64, address));
                    
                    assertEq(emittedExpiry, newExpiry, "Event expiry should match");
                    assertEq(emittedRenewer, renewer, "Event renewer should match");
                }
                
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "MockNameRenewed event not found");
    }

    function test_onRelinquish_emitsEvent() public {
        // First eject the name so the controller owns it and becomes the observer
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint32 roleBitmap = uint32(ALL_ROLES);
        bytes memory ejectionData = _createEjectionData(label, l1Owner, l1Subregistry, l1Resolver, expiryTime, roleBitmap);
        vm.prank(user);
        registry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);
        
        // Verify controller owns the token and is the observer
        assertEq(registry.ownerOf(tokenId), address(controller), "Controller should own the token");
        assertEq(address(registry.tokenObservers(tokenId)), address(controller), "Controller should be the observer");
        
        address relinquisher = address(this);
        
        // Call onRelinquish directly on the controller (simulating a call from the registry)
        vm.recordLogs();
        controller.onRelinquish(tokenId, relinquisher);
        
        // Check for MockNameRelinquished event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        
        bytes32 eventSig = keccak256("MockNameRelinquished(uint256,address)");
        
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(controller) && 
                logs[i].topics[0] == eventSig) {
                
                // For indexed parameters, check that the topics match
                if (logs[i].topics.length > 1) {
                    assertEq(uint256(logs[i].topics[1]), tokenId, "Event tokenId should match");
                }
                
                // Only decode data if there is data to decode
                if (logs[i].data.length > 0) {
                    address emittedRelinquisher = abi.decode(logs[i].data, (address));
                    assertEq(emittedRelinquisher, relinquisher, "Event relinquisher should match");
                }
                
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "MockNameRelinquished event not found");
        
        // Verify token is still owned by the controller (onRelinquish in mock doesn't change ownership)
        assertEq(registry.ownerOf(tokenId), address(controller), "Token should still be owned by controller");
    }

    function test_Revert_eject_invalid_label() public {
        // Prepare the data for ejection with an invalid label
        string memory invalidLabel = "invalid";
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint256 roleBitmap = ALL_ROLES;
        bytes memory ejectionData = _createEjectionData(invalidLabel, l1Owner, l1Subregistry, l1Resolver, expiryTime, roleBitmap);
        
        // Make sure user still owns the token
        assertEq(registry.ownerOf(tokenId), user);
        
        // User transfers the token to the ejection controller, should revert with InvalidLabel
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(L2EjectionController.InvalidLabel.selector, tokenId, invalidLabel));
        registry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);
    }

    function test_Revert_onERC1155Received_CallerNotRegistry() public {
        // Prepare valid data for ejection
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint256 roleBitmap = ALL_ROLES;
        bytes memory ejectionData = _createEjectionData(label, l1Owner, l1Subregistry, l1Resolver, expiryTime, roleBitmap);
        
        // Try to call onERC1155Received directly (not through registry)
        vm.expectRevert(abi.encodeWithSelector(EjectionController.CallerNotRegistry.selector, address(this)));
        controller.onERC1155Received(address(this), user, tokenId, 1, ejectionData);
    }

    function test_Revert_onERC1155BatchReceived_CallerNotRegistry() public {
        // Create batch of tokens to transfer
        uint256[] memory ids = new uint256[](2);
        ids[0] = tokenId;
        ids[1] = tokenId + 1;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;
        
        // Create arrays for transfer data
        string[] memory labels = new string[](2);
        address[] memory owners = new address[](2);
        address[] memory subregistries = new address[](2);
        address[] memory resolvers = new address[](2);
        uint64[] memory expiries = new uint64[](2);
        uint256[] memory roleBitmaps = new uint256[](2);
        
        // Set values for each token
        labels[0] = label;
        labels[1] = "test2";
        
        for (uint256 i = 0; i < 2; i++) {
            owners[i] = l1Owner;
            subregistries[i] = l1Subregistry;
            resolvers[i] = l1Resolver;
            expiries[i] = uint64(block.timestamp + expiryDuration);
            roleBitmaps[i] = ALL_ROLES;
        }
        
        // Create batch ejection data
        bytes memory batchData = _createBatchEjectionData(labels, owners, subregistries, resolvers, expiries, roleBitmaps);
        
        // Try to call onERC1155BatchReceived directly (not through registry)
        vm.expectRevert(abi.encodeWithSelector(EjectionController.CallerNotRegistry.selector, address(this)));
        controller.onERC1155BatchReceived(address(this), user, ids, amounts, batchData);
    }

    // Add a test specifically for role bitmap in transfer data
    function test_ejection_with_role_bitmap() public {
        // Prepare data with different role bitmaps
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        
        uint256 basicRoles = ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY;
        uint256 allRoles = ALL_ROLES;
        uint256 noRoles = 0;
        
        bytes memory data1 = _createEjectionData(label, l1Owner, l1Subregistry, l1Resolver, expiryTime, basicRoles);
        bytes memory data2 = _createEjectionData(label, l1Owner, l1Subregistry, l1Resolver, expiryTime, allRoles);
        bytes memory data3 = _createEjectionData(label, l1Owner, l1Subregistry, l1Resolver, expiryTime, noRoles);
        
        // Verify the role bitmap is set correctly in the encoded data
        TransferData memory decoded1 = abi.decode(data1, (TransferData));
        TransferData memory decoded2 = abi.decode(data2, (TransferData));
        TransferData memory decoded3 = abi.decode(data3, (TransferData));
        
        assertEq(decoded1.roleBitmap, basicRoles, "Basic roles not set correctly");
        assertEq(decoded2.roleBitmap, allRoles, "All roles not set correctly");
        assertEq(decoded3.roleBitmap, noRoles, "No roles not set correctly");
        
        // Test the ejection with a role bitmap
        vm.prank(user);
        registry.safeTransferFrom(user, address(controller), tokenId, 1, data2);
        
        // Verify token is now owned by the controller
        assertEq(registry.ownerOf(tokenId), address(controller), "Token should be owned by the controller");
    }

    // Add test to verify the internal callback methods are correctly called through token observer interface
    function test_tokenObserver_callbacks() public {
        // First eject the name so the controller owns it and becomes the observer
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint32 roleBitmap = uint32(ALL_ROLES);
        bytes memory ejectionData = _createEjectionData(label, l1Owner, l1Subregistry, l1Resolver, expiryTime, roleBitmap);
        vm.prank(user);
        registry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);
        
        // Verify controller owns the token and is the observer
        assertEq(registry.ownerOf(tokenId), address(controller), "Controller should own the token");
        assertEq(address(registry.tokenObservers(tokenId)), address(controller), "Controller should be the observer");
        
        // Reset tracking flags
        controller.resetTracking();
        
        // Test onRenew callback
        uint64 newExpiry = uint64(block.timestamp + expiryDuration * 2);
        address renewer = address(this);
        controller.onRenew(tokenId, newExpiry, renewer);
        assertTrue(controller.onRenewCalled(), "onRenew should call _onRenew");
        
        // Test onRelinquish callback
        address relinquisher = address(this);
        controller.onRelinquish(tokenId, relinquisher);
        assertTrue(controller.onRelinquishCalled(), "onRelinquish should call _onRelinquish");
    }
}

// Mock implementation of L2EjectionController for testing
contract MockL2EjectionController is L2EjectionController {
    // Define event signatures exactly as they will be emitted
    event MockNameEjectedToL1(uint256 indexed tokenId, bytes data);
    event MockNameMigratedFromL1(uint256 indexed tokenId, address l2Owner, address l2Subregistry, address l2Resolver, uint256 roleBitmap);
    event MockNameRenewed(uint256 indexed tokenId, uint64 expires, address renewedBy);
    event MockNameRelinquished(uint256 indexed tokenId, address relinquishedBy);

    // Tracking flags for callback tests
    bool private _onRenewCalled;
    bool private _onRelinquishCalled;

    constructor(IPermissionedRegistry _registry) L2EjectionController(_registry) {}

    // Implement the required external methods
    function onRenew(uint256 tokenId, uint64 expires, address renewedBy) external override {
        _onRenew(tokenId, expires, renewedBy);
    }
    
    function onRelinquish(uint256 tokenId, address relinquishedBy) external override {
        _onRelinquish(tokenId, relinquishedBy);
    }

    /**
     * @dev Overridden to emit a mock event after calling the parent logic.
     */
    function _onEject(uint256[] memory tokenIds, TransferData[] memory transferDataArray) internal override {
        super._onEject(tokenIds, transferDataArray);
        
        // Emit events for each token ID processed
        for (uint256 i = 0; i < tokenIds.length; i++) {
            TransferData memory transferData = transferDataArray[i];
            emit MockNameEjectedToL1(
                tokenIds[i], 
                abi.encode(
                    transferData.label, 
                    transferData.owner, 
                    transferData.subregistry, 
                    transferData.resolver, 
                    transferData.expires
                )
            );
        }
    }

    /**
     * @dev Public wrapper to call the internal _completeMigrationFromL1 for testing.
     */
    function call_completeMigrationFromL1(
        uint256 tokenId,
        address l2Owner,
        address l2Subregistry,
        address l2Resolver,
        uint256 newRoleBitmap
    ) public {
        TransferData memory transferData = TransferData({
            label: "",
            owner: l2Owner,
            subregistry: l2Subregistry,
            resolver: l2Resolver,
            expires: 0,
            roleBitmap: newRoleBitmap
        });
        
        _completeMigrationFromL1(tokenId, transferData);
        emit MockNameMigratedFromL1(tokenId, l2Owner, l2Subregistry, l2Resolver, newRoleBitmap);
    }

    /**
     * @dev Implementation of internal _onRenew method
     */
    function _onRenew(uint256 tokenId, uint64 expires, address renewedBy) internal override {
        _onRenewCalled = true;
        emit MockNameRenewed(tokenId, expires, renewedBy);
    }

    /**
     * @dev Implementation of internal _onRelinquish method
     */
    function _onRelinquish(uint256 tokenId, address relinquishedBy) internal override {
        _onRelinquishCalled = true;
        emit MockNameRelinquished(tokenId, relinquishedBy);
    }
    
    // Helper functions for tests
    function resetTracking() external {
        _onRenewCalled = false;
        _onRelinquishCalled = false;
    }
    
    function onRenewCalled() external view returns (bool) {
        return _onRenewCalled;
    }
    
    function onRelinquishCalled() external view returns (bool) {
        return _onRelinquishCalled;
    }
}
