// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

import {L2BridgeController} from "../src/L2/L2BridgeController.sol";
import {PermissionedRegistry} from "../src/common/PermissionedRegistry.sol";
import {RegistryDatastore} from "../src/common/RegistryDatastore.sol";
import {IRegistryDatastore} from "../src/common/IRegistryDatastore.sol";
import {IRegistryMetadata} from "../src/common/IRegistryMetadata.sol";
import {SimpleRegistryMetadata} from "../src/common/SimpleRegistryMetadata.sol";

import {TransferData} from "../src/common/TransferData.sol";
import {IBridge, BridgeMessageType, LibBridgeRoles} from "../src/common/IBridge.sol";
import {BridgeEncoder} from "../src/common/BridgeEncoder.sol";
import {IPermissionedRegistry} from "../src/common/IPermissionedRegistry.sol";
import {ITokenObserver} from "../src/common/ITokenObserver.sol";
import {IRegistry} from "../src/common/IRegistry.sol";
import {NameUtils} from "../src/common/NameUtils.sol";
import {EjectionController} from "../src/common/EjectionController.sol";
import {LibEACBaseRoles} from "../src/common/EnhancedAccessControl.sol";
import {IEnhancedAccessControl} from "../src/common/IEnhancedAccessControl.sol";
import {LibRegistryRoles} from "../src/common/LibRegistryRoles.sol";

// Mock implementation of IRegistryMetadata
contract MockRegistryMetadata is IRegistryMetadata {
    function tokenUri(uint256) external pure override returns (string memory) {
        return "";
    }
}

// Mock implementation of IBridge for testing
contract MockBridge is IBridge {
    uint256 public sendMessageCallCount;
    bytes public lastMessage;

    function sendMessage(bytes memory message) external override {
        sendMessageCallCount++;
        lastMessage = message;
    }

    function resetCounters() external {
        sendMessageCallCount = 0;
        lastMessage = "";
    }
}

contract TestL2BridgeController is Test, ERC1155Holder {
    L2BridgeController controller;
    PermissionedRegistry ethRegistry;
    RegistryDatastore datastore;
    MockRegistryMetadata registryMetadata;
    MockBridge bridge;

    address user = address(0x1);
    address owner = address(0x2);
    address resolver = address(0x3);
    address l1Owner = address(0x2);
    address l1Subregistry = address(0x3);
    address l1Resolver = address(0x6);
    address l2Owner = address(0x4);
    address l2Subregistry = address(0x5);
    address l2Resolver = address(0x7);

    string testLabel = "test";
    string subdLabel = "sub";
    bytes32 constant ETH_TLD_HASH = keccak256(bytes("eth"));

    uint64 expiryDuration = 86400; // 1 day
    uint256 tokenId;

    function setUp() public {
        // Deploy dependencies
        datastore = new RegistryDatastore();
        registryMetadata = new MockRegistryMetadata();
        bridge = new MockBridge();

        // Deploy ETH registry
        ethRegistry = new PermissionedRegistry(datastore, registryMetadata, address(this), LibEACBaseRoles.ALL_ROLES);

        // Deploy combined bridge controller
        controller = new L2BridgeController(bridge, ethRegistry, datastore);

        // Grant roles to bridge controller for registering names
        ethRegistry.grantRootRoles(LibRegistryRoles.ROLE_REGISTRAR, address(controller));

        // Grant bridge roles to the bridge mock so it can call the controller
        controller.grantRootRoles(LibBridgeRoles.ROLE_EJECTOR, address(bridge));

        // Register a test name
        uint64 expires = uint64(block.timestamp + expiryDuration);
        tokenId = ethRegistry.register(testLabel, user, ethRegistry, address(0), LibEACBaseRoles.ALL_ROLES, expires);
    }

    /**
     * Helper method to create properly encoded data for the ERC1155 transfers
     */
    function _createEjectionData(
        string memory nameLabel,
        address _owner,
        address subregistry,
        address _resolver,
        uint64 expiryTime,
        uint256 roleBitmap
    ) internal pure returns (bytes memory) {
        TransferData memory transferData = TransferData({
            label: nameLabel,
            owner: _owner,
            subregistry: subregistry,
            resolver: _resolver,
            expires: expiryTime,
            roleBitmap: roleBitmap
        });
        return abi.encode(transferData);
    }

    function test_constructor() public view {
        assertEq(address(controller.bridge()), address(bridge));
        assertEq(address(controller.registry()), address(ethRegistry));
        assertEq(address(controller.datastore()), address(datastore));
    }

    // EJECTION TESTS

    function test_eject_flow_via_transfer() public {
        // Prepare the data for ejection with label and expiry
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint256 roleBitmap = LibEACBaseRoles.ALL_ROLES;
        bytes memory ejectionData =
            _createEjectionData(testLabel, l1Owner, l1Subregistry, l1Resolver, expiryTime, roleBitmap);

        // Make sure user still owns the token
        assertEq(ethRegistry.ownerOf(tokenId), user);

        // User transfers the token to the bridge controller
        vm.recordLogs();
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);

        // Check for NameEjectedToL1 event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;

        bytes32 eventSig = keccak256("NameEjectedToL1(bytes,uint256)");

        for (uint256 i = 0; i < logs.length; i++) {
            // Check if this log is our event (emitter and first topic match)
            if (logs[i].emitter == address(controller) && logs[i].topics[0] == eventSig) {
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "NameEjectedToL1 event not found");

        // Verify subregistry is cleared after ejection
        (address subregAddr,,) = datastore.getSubregistry(tokenId);
        assertEq(subregAddr, address(0), "Subregistry not cleared after ejection");

        // Verify token observer is set
        assertEq(address(ethRegistry.tokenObservers(tokenId)), address(controller), "Token observer not set");

        // Verify token is now owned by the controller
        assertEq(ethRegistry.ownerOf(tokenId), address(controller), "Token should be owned by the controller");
    }

    function test_completeEjectionFromL1() public {
        // Use specific roles instead of ALL_ROLES, including admin roles that are now required
        uint256 originalRoles = LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_SUBREGISTRY
            | LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER | LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER_ADMIN
            | LibRegistryRoles.ROLE_SET_SUBREGISTRY_ADMIN;
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);

        string memory label2 = "test2";
        uint256 tokenId2 = ethRegistry.register(label2, user, ethRegistry, address(0), originalRoles, expiryTime);

        // First eject the name so the controller owns it
        bytes memory ejectionData =
            _createEjectionData(label2, l1Owner, l1Subregistry, l1Resolver, expiryTime, originalRoles);
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), tokenId2, 1, ejectionData);

        // Verify controller owns the token
        assertEq(ethRegistry.ownerOf(tokenId2), address(controller), "Controller should own the token");

        // Try to migrate with different roles than the original ones - these should be ignored
        uint256 differentRoles = LibRegistryRoles.ROLE_RENEW | LibRegistryRoles.ROLE_REGISTRAR;
        vm.recordLogs();
        TransferData memory migrationData = TransferData({
            label: label2,
            owner: l2Owner,
            subregistry: l2Subregistry,
            resolver: l2Resolver,
            expires: 0,
            roleBitmap: differentRoles
        });

        // Call through the bridge (using vm.prank to simulate bridge calling)
        vm.prank(address(bridge));
        controller.completeEjectionFromL1(migrationData);

        // Verify ejection results
        _verifyEjectionResults(tokenId2, label2, originalRoles, differentRoles);
        _verifyEjectionEvent(tokenId2, differentRoles);
    }

    // Helper function to verify ejection results
    function _verifyEjectionResults(uint256 _tokenId, string memory _label, uint256 originalRoles, uint256 ignoredRoles)
        internal
        view
    {
        // Verify name was migrated - check ownership transfer
        assertEq(ethRegistry.ownerOf(_tokenId), l2Owner, "L2 owner should now own the token");

        // Verify subregistry and resolver were set correctly
        IRegistry subregAddr = ethRegistry.getSubregistry(_label);
        assertEq(address(subregAddr), l2Subregistry, "Subregistry not set correctly after migration");

        address resolverAddr = ethRegistry.getResolver(_label);
        assertEq(resolverAddr, l2Resolver, "Resolver not set correctly after migration");

        // ROLE BITMAP VERIFICATION:
        bytes32 resource = ethRegistry.getTokenIdResource(_tokenId);
        assertTrue(ethRegistry.hasRoles(resource, originalRoles, l2Owner), "L2 owner should have original roles");
        assertFalse(ethRegistry.hasRoles(resource, ignoredRoles, l2Owner), "L2 owner should not have new roles");
    }

    // Helper function to check for event emission
    function _verifyEjectionEvent(uint256, /* _tokenId */ uint256 /* expectedRoleBitmap */ ) internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;

        bytes32 eventSig = keccak256("NameEjectedToL2(bytes,uint256)");

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(controller) && logs[i].topics[0] == eventSig) {
                foundEvent = true;
                break;
            }
        }

        assertTrue(foundEvent, "NameEjectedToL2 event not found");
    }

    function test_Revert_completeEjectionFromL1_notOwner() public {
        // Expect revert with NotTokenOwner error from the L2BridgeController logic
        vm.expectRevert(abi.encodeWithSelector(L2BridgeController.NotTokenOwner.selector, tokenId));
        // Call the external method which should revert
        TransferData memory migrationData = TransferData({
            label: testLabel,
            owner: l2Owner,
            subregistry: l2Subregistry,
            resolver: l2Resolver,
            expires: 0,
            roleBitmap: LibEACBaseRoles.ALL_ROLES
        });
        // Call through the bridge (using vm.prank to simulate bridge calling)
        vm.prank(address(bridge));
        controller.completeEjectionFromL1(migrationData);
    }

    function test_Revert_completeEjectionFromL1_not_bridge() public {
        // Try to call completeEjectionFromL1 directly (without proper role)
        TransferData memory transferData = TransferData({
            label: testLabel,
            owner: l2Owner,
            subregistry: l2Subregistry,
            resolver: l2Resolver,
            expires: 0,
            roleBitmap: LibEACBaseRoles.ALL_ROLES
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                bytes32(0), // ROOT_RESOURCE
                LibBridgeRoles.ROLE_EJECTOR,
                address(this)
            )
        );
        controller.completeEjectionFromL1(transferData);
    }

    function test_supportsInterface() public view {
        assertTrue(controller.supportsInterface(type(EjectionController).interfaceId));
        assertTrue(controller.supportsInterface(type(IERC1155Receiver).interfaceId));
        assertTrue(controller.supportsInterface(type(ITokenObserver).interfaceId));
        assertFalse(controller.supportsInterface(0x12345678));
    }

    function test_onRenew_sendsBridgeMessage() public {
        // First eject the name so the controller owns it and becomes the observer
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint32 roleBitmap = uint32(LibEACBaseRoles.ALL_ROLES);
        bytes memory ejectionData =
            _createEjectionData(testLabel, l1Owner, l1Subregistry, l1Resolver, expiryTime, roleBitmap);
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);

        // Verify controller owns the token and is the observer
        assertEq(ethRegistry.ownerOf(tokenId), address(controller), "Controller should own the token");
        assertEq(address(ethRegistry.tokenObservers(tokenId)), address(controller), "Controller should be the observer");

        uint64 newExpiry = uint64(block.timestamp + expiryDuration * 2);
        address renewer = address(this);

        // Reset bridge counters
        bridge.resetCounters();

        // Call onRenew directly on the controller (simulating a call from the registry)
        controller.onRenew(tokenId, newExpiry, renewer);

        // Verify bridge message was sent
        assertEq(bridge.sendMessageCallCount(), 1, "Bridge should have been called once");

        // Verify the message content
        bytes memory lastMessage = bridge.lastMessage();
        assertTrue(lastMessage.length > 0, "Message should not be empty");

        // Decode and verify the renewal message
        BridgeMessageType messageType = BridgeEncoder.getMessageType(lastMessage);
        assertEq(uint256(messageType), uint256(BridgeMessageType.RENEWAL), "Message should be a renewal");

        (uint256 decodedTokenId, uint64 decodedExpiry) = BridgeEncoder.decodeRenewal(lastMessage);
        assertEq(decodedTokenId, tokenId, "Token ID should match");
        assertEq(decodedExpiry, newExpiry, "Expiry should match");
    }

    function test_Revert_eject_invalid_label() public {
        // Prepare the data for ejection with an invalid label
        string memory invalidLabel = "invalid";
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint256 roleBitmap = LibEACBaseRoles.ALL_ROLES;
        bytes memory ejectionData =
            _createEjectionData(invalidLabel, l1Owner, l1Subregistry, l1Resolver, expiryTime, roleBitmap);

        // Make sure user still owns the token
        assertEq(ethRegistry.ownerOf(tokenId), user);

        // User transfers the token to the bridge controller, should revert with InvalidLabel
        vm.expectRevert(abi.encodeWithSelector(EjectionController.InvalidLabel.selector, tokenId, invalidLabel));
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);
    }

    function test_Revert_onERC1155Received_UnauthorizedCaller() public {
        // Prepare valid data for ejection
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint256 roleBitmap = LibEACBaseRoles.ALL_ROLES;
        bytes memory ejectionData =
            _createEjectionData(testLabel, l1Owner, l1Subregistry, l1Resolver, expiryTime, roleBitmap);

        // Try to call onERC1155Received directly (not through registry)
        vm.expectRevert(abi.encodeWithSelector(EjectionController.UnauthorizedCaller.selector, address(this)));
        controller.onERC1155Received(address(this), user, tokenId, 1, ejectionData);
    }

    function test_tokenObserver_functionality() public {
        // First eject the name so the controller owns it and becomes the observer
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint32 roleBitmap = uint32(LibEACBaseRoles.ALL_ROLES);
        bytes memory ejectionData =
            _createEjectionData(testLabel, l1Owner, l1Subregistry, l1Resolver, expiryTime, roleBitmap);
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);

        // Verify controller owns the token and is the observer
        assertEq(ethRegistry.ownerOf(tokenId), address(controller), "Controller should own the token");
        assertEq(address(ethRegistry.tokenObservers(tokenId)), address(controller), "Controller should be the observer");

        // Reset bridge counters
        bridge.resetCounters();

        // Test onRenew callback - should send bridge message
        uint64 newExpiry = uint64(block.timestamp + expiryDuration * 2);
        address renewer = address(this);
        controller.onRenew(tokenId, newExpiry, renewer);
        assertEq(bridge.sendMessageCallCount(), 1, "onRenew should send bridge message");
    }

    function test_Revert_eject_tooManyRoleAssignees() public {
        // Test multiple error scenarios: too many assignees and missing assignees
        string memory testLabel2 = "testbadassignees";
        uint64 expires = uint64(block.timestamp + expiryDuration);

        // Scenario 1: Register with only one critical role (missing ROLE_SET_SUBREGISTRY)
        uint256 tokenId2 = ethRegistry.register(
            testLabel2, user, ethRegistry, address(0), LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER, expires
        );

        uint256 criticalRoles = LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER
            | LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER_ADMIN | LibRegistryRoles.ROLE_SET_SUBREGISTRY
            | LibRegistryRoles.ROLE_SET_SUBREGISTRY_ADMIN;
        bytes memory ejectionData =
            _createEjectionData(testLabel2, l1Owner, l1Subregistry, l1Resolver, expires, criticalRoles);

        // Should fail due to missing ROLE_SET_SUBREGISTRY and admin roles
        vm.expectRevert(
            abi.encodeWithSelector(L2BridgeController.TooManyRoleAssignees.selector, tokenId2, criticalRoles)
        );
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), tokenId2, 1, ejectionData);

        // Scenario 2: Grant the missing roles, then add extra assignees
        ethRegistry.grantRoles(bytes32(tokenId2), LibRegistryRoles.ROLE_SET_SUBREGISTRY, user);
        ethRegistry.grantRoles(bytes32(tokenId2), LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER_ADMIN, user);
        ethRegistry.grantRoles(bytes32(tokenId2), LibRegistryRoles.ROLE_SET_SUBREGISTRY_ADMIN, user);
        address secondUser = address(0x999);
        ethRegistry.grantRoles(bytes32(tokenId2), LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER, secondUser);

        // Get the current token ID after regeneration
        (uint256 currentTokenId,,) = ethRegistry.getNameData(testLabel2);

        // Should fail due to multiple assignees for ROLE_SET_TOKEN_OBSERVER
        vm.expectRevert(
            abi.encodeWithSelector(L2BridgeController.TooManyRoleAssignees.selector, currentTokenId, criticalRoles)
        );
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), currentTokenId, 1, ejectionData);
    }

    function test_eject_success_exactlyOneAssigneePerRole() public {
        // Test successful ejection when each critical role has exactly one assignee
        string memory testLabel3 = "testgoodassignees";
        uint64 expires = uint64(block.timestamp + expiryDuration);

        uint256 criticalRoles = LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER
            | LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER_ADMIN | LibRegistryRoles.ROLE_SET_SUBREGISTRY
            | LibRegistryRoles.ROLE_SET_SUBREGISTRY_ADMIN;
        uint256 tokenId3 = ethRegistry.register(testLabel3, user, ethRegistry, address(0), criticalRoles, expires);

        // Verify exactly one assignee per critical role
        (uint256 counts, uint256 mask) = ethRegistry.getAssigneeCount(bytes32(tokenId3), criticalRoles);
        assertEq(counts & mask, criticalRoles, "Should have exactly one assignee for each critical role");

        bytes memory ejectionData =
            _createEjectionData(testLabel3, l1Owner, l1Subregistry, l1Resolver, expires, criticalRoles);

        vm.recordLogs();
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), tokenId3, 1, ejectionData);

        // Verify successful ejection
        assertEq(
            ethRegistry.ownerOf(tokenId3), address(controller), "Token should be owned by controller after ejection"
        );
        assertEq(
            address(ethRegistry.tokenObservers(tokenId3)),
            address(controller),
            "Token observer should be set to controller"
        );

        // Verify event emission
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == address(controller)
                    && logs[i].topics[0] == keccak256("NameEjectedToL1(bytes,uint256)")
            ) {
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "NameEjectedToL1 event should be emitted");
    }

    function test_eject_success_resolverRolesIgnored() public {
        // Test that resolver roles don't affect ejection (can have multiple or zero assignees)
        string memory testLabel4 = "testresolverignored";
        uint64 expires = uint64(block.timestamp + expiryDuration);

        // Only grant critical roles initially
        uint256 criticalRoles = LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER
            | LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER_ADMIN | LibRegistryRoles.ROLE_SET_SUBREGISTRY
            | LibRegistryRoles.ROLE_SET_SUBREGISTRY_ADMIN;
        uint256 tokenId4 = ethRegistry.register(testLabel4, user, ethRegistry, address(0), criticalRoles, expires);

        // Get the resource ID (this stays stable across regenerations)
        bytes32 resourceId = ethRegistry.getTokenIdResource(tokenId4);

        // Add multiple assignees to ROLE_SET_RESOLVER (this should not affect ejection)
        address user2 = address(0x666);
        address user3 = address(0x555);
        ethRegistry.grantRoles(resourceId, LibRegistryRoles.ROLE_SET_RESOLVER, user);
        ethRegistry.grantRoles(resourceId, LibRegistryRoles.ROLE_SET_RESOLVER, user2);
        ethRegistry.grantRoles(resourceId, LibRegistryRoles.ROLE_SET_RESOLVER, user3);

        // Get the current token ID after regeneration
        (uint256 currentTokenId,,) = ethRegistry.getNameData(testLabel4);

        bytes memory ejectionData = _createEjectionData(testLabel4, l1Owner, l1Subregistry, l1Resolver, expires, 0);

        // Ejection should succeed despite multiple resolver role assignees
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), currentTokenId, 1, ejectionData);

        assertEq(ethRegistry.ownerOf(currentTokenId), address(controller), "Ejection should succeed");
    }
}
