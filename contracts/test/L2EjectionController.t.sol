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

// Mock implementation of IRegistryMetadata
contract MockRegistryMetadata is IRegistryMetadata {
    function tokenUri(uint256) external pure override returns (string memory) {
        return "";
    }
}

// Mock implementation of L2EjectionController for testing abstract contract
contract MockL2EjectionController is L2EjectionController {
    // Define event signatures exactly as they will be emitted
    event MockNameEjectedToL1(uint256 indexed tokenId, bytes data);
    event MockNameMigratedFromL1(uint256 indexed tokenId, address l2Owner, address l2Subregistry, address l2Resolver);
    event MockNameRenewed(uint256 indexed tokenId, uint64 expires, address renewedBy);
    event MockNameRelinquished(uint256 indexed tokenId, address relinquishedBy);

    constructor(IPermissionedRegistry _registry) L2EjectionController(_registry) {}

    /**
     * @dev Overridden to emit a mock event after calling the parent logic.
     */
    function _onEject(uint256 tokenId, EjectionController.TransferData memory transferData) internal override {
        super._onEject(tokenId, transferData);
        emit MockNameEjectedToL1(tokenId, abi.encode(transferData.label, transferData.newOwner, transferData.newSubregistry, transferData.newResolver, transferData.newExpires));
    }

    /**
     * @dev Public wrapper to call the internal _completeMigrationFromL1 for testing.
     */
    function call_completeMigrationFromL1(
        uint256 tokenId,
        address l2Owner,
        address l2Subregistry,
        address l2Resolver
    ) public {
        _completeMigrationFromL1(tokenId, l2Owner, l2Subregistry, l2Resolver);
        emit MockNameMigratedFromL1(tokenId, l2Owner, l2Subregistry, l2Resolver);
    }

    /**
     * @dev Implementation of abstract function, emits mock event.
     */
    function onRenew(uint256 tokenId, uint64 expires, address renewedBy) external override {
        emit MockNameRenewed(tokenId, expires, renewedBy);
    }

    /**
     * @dev Implementation of abstract function, emits mock event.
     */
    function onRelinquish(uint256 tokenId, address relinquishedBy) external override {
        emit MockNameRelinquished(tokenId, relinquishedBy);
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
        uint64 expiryTime
    ) internal pure returns (bytes memory) {
        EjectionController.TransferData memory transferData = EjectionController.TransferData({
            label: nameLabel,
            newOwner: owner,
            newSubregistry: subregistry,
            newResolver: resolver,
            newExpires: expiryTime
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
        uint64[] memory expiryTimes
    ) internal pure returns (bytes memory) {
        require(labels.length == owners.length && 
                labels.length == subregistries.length && 
                labels.length == resolvers.length && 
                labels.length == expiryTimes.length, 
                "Array lengths must match");
                
        EjectionController.TransferData[] memory transferDataArray = new EjectionController.TransferData[](labels.length);
        
        for (uint256 i = 0; i < labels.length; i++) {
            transferDataArray[i] = EjectionController.TransferData({
                label: labels[i],
                newOwner: owners[i],
                newSubregistry: subregistries[i],
                newResolver: resolvers[i],
                newExpires: expiryTimes[i]
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
        bytes memory ejectionData = _createEjectionData(label, l1Owner, l1Subregistry, l1Resolver, expiryTime);
        
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
        // First eject the name so the controller owns it
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        bytes memory ejectionData = _createEjectionData(label, l1Owner, l1Subregistry, l1Resolver, expiryTime);
        vm.prank(user);
        registry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);
        
        // Verify controller owns the token
        assertEq(registry.ownerOf(tokenId), address(controller), "Controller should own the token");
        
        // Call the migration function via the public wrapper
        vm.recordLogs();
        controller.call_completeMigrationFromL1(tokenId, l2Owner, l2Subregistry, l2Resolver);
        
        // Check for MockNameMigratedFromL1 event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        
        bytes32 eventSig = keccak256("MockNameMigratedFromL1(uint256,address,address,address)");
        
        for (uint i = 0; i < logs.length; i++) {
            // Check if this log is our event (emitter and first topic match)
            if (logs[i].emitter == address(controller) && 
                logs[i].topics[0] == eventSig) {
                
                // For indexed parameters, check that the topics match
                if (logs[i].topics.length > 1) {
                    assertEq(uint256(logs[i].topics[1]), tokenId);
                }
                
                // Only decode data if there is data to decode
                if (logs[i].data.length > 0) {
                    (address emittedL2Owner, address emittedL2Subregistry, address emittedL2Resolver) = 
                        abi.decode(logs[i].data, (address, address, address));
                    
                    // Verify all data fields match expected values
                    assertEq(emittedL2Owner, l2Owner);
                    assertEq(emittedL2Subregistry, l2Subregistry);
                    assertEq(emittedL2Resolver, l2Resolver);
                }
                
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "MockNameMigratedFromL1 event not found");
        
        // Verify subregistry and resolver were set correctly
        IRegistry subregAddr = registry.getSubregistry(label);
        assertEq(address(subregAddr), l2Subregistry, "Subregistry not set correctly after migration");
        
        address resolverAddr = registry.getResolver(label);
        assertEq(resolverAddr, l2Resolver, "Resolver not set correctly after migration");
        
        // Verify token ownership transferred
        assertEq(registry.ownerOf(tokenId), l2Owner, "Token ownership not transferred after migration");
    }

    function test_Revert_completeMigrationFromL1_notOwner() public {
        // Expect revert with NotTokenOwner error from the L2EjectionController logic
        vm.expectRevert(abi.encodeWithSelector(L2EjectionController.NotTokenOwner.selector, tokenId));
        // Call the public wrapper which invokes the internal logic that should revert
        controller.call_completeMigrationFromL1(tokenId, l2Owner, l2Subregistry, l2Resolver);
    }

    function test_supportsInterface() public view {
        assertTrue(controller.supportsInterface(type(EjectionController).interfaceId));
        assertTrue(controller.supportsInterface(type(IERC1155Receiver).interfaceId));
        // Remove test for ITokenObserver until we confirm it's actually implemented
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
        
        // Set values for each token
        labels[0] = label2;
        labels[1] = label3;
        
        for (uint256 i = 0; i < 2; i++) {
            owners[i] = l1Owner;
            subregistries[i] = l1Subregistry;
            resolvers[i] = l1Resolver;
            expiries[i] = uint64(block.timestamp + expiryDuration);
        }
        
        // Create batch ejection data
        bytes memory batchData = _createBatchEjectionData(labels, owners, subregistries, resolvers, expiries);
        
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
        bytes memory ejectionData = _createEjectionData(label, l1Owner, l1Subregistry, l1Resolver, expiryTime);
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
                    assertEq(uint256(logs[i].topics[1]), tokenId);
                }
                
                // Only decode data if there is data to decode
                if (logs[i].data.length > 0) {
                    (uint64 emittedExpiry, address emittedRenewer) = 
                        abi.decode(logs[i].data, (uint64, address));
                    
                    assertEq(emittedExpiry, newExpiry);
                    assertEq(emittedRenewer, renewer);
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
        bytes memory ejectionData = _createEjectionData(label, l1Owner, l1Subregistry, l1Resolver, expiryTime);
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
                    assertEq(uint256(logs[i].topics[1]), tokenId);
                }
                
                // Only decode data if there is data to decode
                if (logs[i].data.length > 0) {
                    address emittedRelinquisher = abi.decode(logs[i].data, (address));
                    assertEq(emittedRelinquisher, relinquisher);
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
        bytes memory ejectionData = _createEjectionData(invalidLabel, l1Owner, l1Subregistry, l1Resolver, expiryTime);
        
        // Make sure user still owns the token
        assertEq(registry.ownerOf(tokenId), user);
        
        // User transfers the token to the ejection controller, should revert with InvalidLabel
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(L2EjectionController.InvalidLabel.selector, tokenId, invalidLabel));
        registry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);
    }
}