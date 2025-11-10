// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering, one-contract-per-file

import {Test, Vm} from "forge-std/Test.sol";

import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {EACBaseRolesLib} from "~src/common/access-control/EnhancedAccessControl.sol";
import {
    IEnhancedAccessControl
} from "~src/common/access-control/interfaces/IEnhancedAccessControl.sol";
import {EjectionController} from "~src/common/bridge/EjectionController.sol";
import {IBridge, BridgeMessageType} from "~src/common/bridge/interfaces/IBridge.sol";
import {BridgeEncoderLib} from "~src/common/bridge/libraries/BridgeEncoderLib.sol";
import {BridgeRolesLib} from "~src/common/bridge/libraries/BridgeRolesLib.sol";
import {TransferData} from "~src/common/bridge/types/TransferData.sol";
import {InvalidOwner, UnauthorizedCaller} from "~src/common/CommonErrors.sol";
import {IRegistry} from "~src/common/registry/interfaces/IRegistry.sol";
import {IRegistryMetadata} from "~src/common/registry/interfaces/IRegistryMetadata.sol";
import {ITokenObserver} from "~src/common/registry/interfaces/ITokenObserver.sol";
import {RegistryRolesLib} from "~src/common/registry/libraries/RegistryRolesLib.sol";
import {RegistryDatastore} from "~src/common/registry/RegistryDatastore.sol";
import {LibLabel} from "~src/common/utils/LibLabel.sol";
import {L2BridgeController} from "~src/L2/bridge/L2BridgeController.sol";
import {PermissionedRegistry} from "~src/common/registry/PermissionedRegistry.sol";

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
        ethRegistry = new PermissionedRegistry(
            datastore,
            registryMetadata,
            address(this),
            EACBaseRolesLib.ALL_ROLES
        );

        // Deploy combined bridge controller
        controller = new L2BridgeController(bridge, ethRegistry, datastore);

        // Grant roles to bridge controller for registering names
        ethRegistry.grantRootRoles(RegistryRolesLib.ROLE_REGISTRAR, address(controller));

        // Grant bridge roles to the bridge mock so it can call the controller
        controller.grantRootRoles(BridgeRolesLib.ROLE_EJECTOR, address(bridge));

        // Register a test name
        uint64 expires = uint64(block.timestamp + expiryDuration);
        tokenId = ethRegistry.register(
            testLabel,
            user,
            ethRegistry,
            address(0),
            EACBaseRolesLib.ALL_ROLES,
            expires
        );
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
            dnsEncodedName: LibLabel.dnsEncodeEthLabel(nameLabel),
            owner: _owner,
            subregistry: subregistry,
            resolver: _resolver,
            roleBitmap: roleBitmap,
            expires: expiryTime
        });
        return abi.encode(transferData);
    }

    function test_constructor() public view {
        assertEq(address(controller.BRIDGE()), address(bridge));
        assertEq(address(controller.REGISTRY()), address(ethRegistry));
        assertEq(address(controller.DATASTORE()), address(datastore));
    }

    // EJECTION TESTS

    function test_eject_flow_via_transfer() public {
        // Prepare the data for ejection with label and expiry
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint256 roleBitmap = EACBaseRolesLib.ALL_ROLES;
        bytes memory ejectionData = _createEjectionData(
            testLabel,
            l1Owner,
            l1Subregistry,
            l1Resolver,
            expiryTime,
            roleBitmap
        );

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
        address subregAddr = datastore.getEntry(address(ethRegistry), tokenId).subregistry;
        assertEq(subregAddr, address(0), "Subregistry not cleared after ejection");

        // Verify token observer is set
        assertEq(
            address(ethRegistry.getTokenObserver(tokenId)),
            address(controller),
            "Token observer not set"
        );

        // Verify token is owned by the controller
        assertEq(
            ethRegistry.ownerOf(tokenId),
            address(controller),
            "Token should be owned by the controller"
        );
    }

    function test_completeEjectionToL2() public {
        // Use specific roles rather than ALL_ROLES, including required admin roles
        uint256 originalRoles = RegistryRolesLib.ROLE_SET_RESOLVER |
            RegistryRolesLib.ROLE_SET_SUBREGISTRY |
            RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER |
            RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER_ADMIN |
            RegistryRolesLib.ROLE_SET_SUBREGISTRY_ADMIN |
            RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN;
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);

        string memory label2 = "test2";
        uint256 tokenId2 = ethRegistry.register(
            label2,
            user,
            ethRegistry,
            address(0),
            originalRoles,
            expiryTime
        );

        // First eject the name so the controller owns it
        bytes memory ejectionData = _createEjectionData(
            label2,
            l1Owner,
            l1Subregistry,
            l1Resolver,
            expiryTime,
            originalRoles
        );
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), tokenId2, 1, ejectionData);

        // Verify controller owns the token
        assertEq(
            ethRegistry.ownerOf(tokenId2),
            address(controller),
            "Controller should own the token"
        );

        // Try to migrate with different roles than the original ones - these should be ignored
        uint256 differentRoles = RegistryRolesLib.ROLE_RENEW | RegistryRolesLib.ROLE_REGISTRAR;
        vm.recordLogs();
        TransferData memory migrationData = TransferData({
            dnsEncodedName: LibLabel.dnsEncodeEthLabel(label2),
            owner: l2Owner,
            subregistry: l2Subregistry,
            resolver: l2Resolver,
            roleBitmap: differentRoles,
            expires: 0
        });

        // Call through the bridge (using vm.prank to simulate bridge calling)
        vm.prank(address(bridge));
        controller.completeEjectionToL2(migrationData);

        // Verify ejection results
        _verifyEjectionResults(tokenId2, label2, originalRoles, differentRoles);
        _verifyEjectionEvent(tokenId2, differentRoles);
    }

    // Helper function to verify ejection results
    function _verifyEjectionResults(
        uint256 _tokenId,
        string memory _label,
        uint256 originalRoles,
        uint256 ignoredRoles
    ) internal view {
        // Verify name was migrated - check ownership transfer
        assertEq(ethRegistry.ownerOf(_tokenId), l2Owner, "L2 owner should now own the token");

        // Verify subregistry and resolver were set correctly
        IRegistry subregAddr = ethRegistry.getSubregistry(_label);
        assertEq(
            address(subregAddr),
            l2Subregistry,
            "Subregistry not set correctly after migration"
        );

        address resolverAddr = ethRegistry.getResolver(_label);
        assertEq(resolverAddr, l2Resolver, "Resolver not set correctly after migration");

        // ROLE BITMAP VERIFICATION:
        uint256 resource = ethRegistry.getResource(_tokenId);
        assertTrue(
            ethRegistry.hasRoles(resource, originalRoles, l2Owner),
            "L2 owner should have original roles"
        );
        assertFalse(
            ethRegistry.hasRoles(resource, ignoredRoles, l2Owner),
            "L2 owner should not have new roles"
        );
    }

    // Helper function to check for event emission
    function _verifyEjectionEvent(
        uint256 /* _tokenId */,
        uint256 /* expectedRoleBitmap */
    ) internal {
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

    function test_Revert_completeEjectionToL2_notOwner() public {
        // Expect revert with NotTokenOwner error from the L2BridgeController logic
        vm.expectRevert(abi.encodeWithSelector(L2BridgeController.NotTokenOwner.selector, tokenId));
        // Call the external method which should revert
        TransferData memory migrationData = TransferData({
            dnsEncodedName: LibLabel.dnsEncodeEthLabel(testLabel),
            owner: l2Owner,
            subregistry: l2Subregistry,
            resolver: l2Resolver,
            roleBitmap: EACBaseRolesLib.ALL_ROLES,
            expires: 0
        });
        // Call through the bridge (using vm.prank to simulate bridge calling)
        vm.prank(address(bridge));
        controller.completeEjectionToL2(migrationData);
    }

    function test_Revert_completeEjectionToL2_not_bridge() public {
        // Try to call completeEjectionToL2 directly (without proper role)
        TransferData memory transferData = TransferData({
            dnsEncodedName: LibLabel.dnsEncodeEthLabel(testLabel),
            owner: l2Owner,
            subregistry: l2Subregistry,
            resolver: l2Resolver,
            roleBitmap: EACBaseRolesLib.ALL_ROLES,
            expires: 0
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                0, // ROOT_RESOURCE
                BridgeRolesLib.ROLE_EJECTOR,
                address(this)
            )
        );
        controller.completeEjectionToL2(transferData);
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
        uint32 roleBitmap = uint32(EACBaseRolesLib.ALL_ROLES);
        bytes memory ejectionData = _createEjectionData(
            testLabel,
            l1Owner,
            l1Subregistry,
            l1Resolver,
            expiryTime,
            roleBitmap
        );
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);

        // Verify controller owns the token and is the observer
        assertEq(
            ethRegistry.ownerOf(tokenId),
            address(controller),
            "Controller should own the token"
        );
        assertEq(
            address(ethRegistry.getTokenObserver(tokenId)),
            address(controller),
            "Controller should be the observer"
        );

        uint64 newExpiry = uint64(block.timestamp + expiryDuration * 2);

        // Reset bridge counters
        bridge.resetCounters();

        // Call onRenew via registry's renew function to properly simulate real usage
        // Grant the controller permission to renew the token
        ethRegistry.grantRoles(tokenId, RegistryRolesLib.ROLE_RENEW, address(controller));

        // Call renew on the registry, which will trigger onRenew on the token observer
        vm.prank(address(controller));
        ethRegistry.renew(tokenId, newExpiry);

        // Verify bridge message was sent
        assertEq(bridge.sendMessageCallCount(), 1, "Bridge should have been called once");

        // Verify the message content
        bytes memory lastMessage = bridge.lastMessage();
        assertTrue(lastMessage.length > 0, "Message should not be empty");

        // Decode and verify the renewal message
        BridgeMessageType messageType = BridgeEncoderLib.getMessageType(lastMessage);
        assertEq(
            uint256(messageType),
            uint256(BridgeMessageType.RENEWAL),
            "Message should be a renewal"
        );

        (uint256 decodedTokenId, uint64 decodedExpiry) = BridgeEncoderLib.decodeRenewal(
            lastMessage
        );
        assertEq(decodedTokenId, tokenId, "Token ID should match");
        assertEq(decodedExpiry, newExpiry, "Expiry should match");
    }

    function test_Revert_eject_invalid_label() public {
        // Prepare the data for ejection with an invalid label
        string memory invalidLabel = "invalid";
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint256 roleBitmap = EACBaseRolesLib.ALL_ROLES;
        bytes memory ejectionData = _createEjectionData(
            invalidLabel,
            l1Owner,
            l1Subregistry,
            l1Resolver,
            expiryTime,
            roleBitmap
        );

        // Make sure user still owns the token
        assertEq(ethRegistry.ownerOf(tokenId), user);

        // User transfers the token to the bridge controller, should revert with InvalidLabel
        vm.expectRevert(
            abi.encodeWithSelector(EjectionController.InvalidLabel.selector, tokenId, invalidLabel)
        );
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);
    }

    function test_Revert_onERC1155Received_UnauthorizedCaller() public {
        // Prepare valid data for ejection
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint256 roleBitmap = EACBaseRolesLib.ALL_ROLES;
        bytes memory ejectionData = _createEjectionData(
            testLabel,
            l1Owner,
            l1Subregistry,
            l1Resolver,
            expiryTime,
            roleBitmap
        );

        // Try to call onERC1155Received directly (not through registry)
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector, address(this)));
        controller.onERC1155Received(address(this), user, tokenId, 1, ejectionData);
    }

    function test_tokenObserver_functionality() public {
        // First eject the name so the controller owns it and becomes the observer
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint32 roleBitmap = uint32(EACBaseRolesLib.ALL_ROLES);
        bytes memory ejectionData = _createEjectionData(
            testLabel,
            l1Owner,
            l1Subregistry,
            l1Resolver,
            expiryTime,
            roleBitmap
        );
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);

        // Verify controller owns the token and is the observer
        assertEq(
            ethRegistry.ownerOf(tokenId),
            address(controller),
            "Controller should own the token"
        );
        assertEq(
            address(ethRegistry.getTokenObserver(tokenId)),
            address(controller),
            "Controller should be the observer"
        );

        // Reset bridge counters
        bridge.resetCounters();

        // Test onRenew callback - should send bridge message
        uint64 newExpiry = uint64(block.timestamp + expiryDuration * 2);
        // Grant the controller permission to renew the token
        ethRegistry.grantRoles(tokenId, RegistryRolesLib.ROLE_RENEW, address(controller));

        // Call renew on the registry, which will trigger onRenew on the token observer
        vm.prank(address(controller));
        ethRegistry.renew(tokenId, newExpiry);
        assertEq(bridge.sendMessageCallCount(), 1, "onRenew should send bridge message");
    }

    function test_Revert_onRenew_UnauthorizedCaller() public {
        // First eject the name so the controller owns it and becomes the observer
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint32 roleBitmap = uint32(EACBaseRolesLib.ALL_ROLES);
        bytes memory ejectionData = _createEjectionData(
            testLabel,
            l1Owner,
            l1Subregistry,
            l1Resolver,
            expiryTime,
            roleBitmap
        );
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);

        uint64 newExpiry = uint64(block.timestamp + expiryDuration * 2);

        // Try to call onRenew directly from an unauthorized address (not the registry)
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector, address(this)));
        controller.onRenew(tokenId, newExpiry, address(this));
    }

    function test_Revert_onRenew_UnauthorizedCaller_randomUser() public {
        // First eject the name so the controller owns it and becomes the observer
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint32 roleBitmap = uint32(EACBaseRolesLib.ALL_ROLES);
        bytes memory ejectionData = _createEjectionData(
            testLabel,
            l1Owner,
            l1Subregistry,
            l1Resolver,
            expiryTime,
            roleBitmap
        );
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);

        uint64 newExpiry = uint64(block.timestamp + expiryDuration * 2);
        address randomUser = address(0x9999);

        // Try to call onRenew from a random user (not the registry)
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector, randomUser));
        vm.prank(randomUser);
        controller.onRenew(tokenId, newExpiry, randomUser);
    }

    function test_onRenew_onlyCallableByRegistry() public {
        // First eject the name so the controller owns it and becomes the observer
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint32 roleBitmap = uint32(EACBaseRolesLib.ALL_ROLES);
        bytes memory ejectionData = _createEjectionData(
            testLabel,
            l1Owner,
            l1Subregistry,
            l1Resolver,
            expiryTime,
            roleBitmap
        );
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);

        uint64 newExpiry = uint64(block.timestamp + expiryDuration * 2);

        // Reset bridge counters
        bridge.resetCounters();

        // Only the registry should be able to call onRenew
        vm.prank(address(ethRegistry));
        controller.onRenew(tokenId, newExpiry, address(this));

        // Verify bridge message was sent
        assertEq(bridge.sendMessageCallCount(), 1, "Bridge should have been called once");

        // Verify the message content
        bytes memory lastMessage = bridge.lastMessage();
        assertTrue(lastMessage.length > 0, "Message should not be empty");

        // Decode and verify the renewal message
        BridgeMessageType messageType = BridgeEncoderLib.getMessageType(lastMessage);
        assertEq(
            uint256(messageType),
            uint256(BridgeMessageType.RENEWAL),
            "Message should be a renewal"
        );

        (uint256 decodedTokenId, uint64 decodedExpiry) = BridgeEncoderLib.decodeRenewal(
            lastMessage
        );
        assertEq(decodedTokenId, tokenId, "Token ID should match");
        assertEq(decodedExpiry, newExpiry, "Expiry should match");
    }

    function test_Revert_eject_tooManyRoleAssignees() public {
        // Test multiple error scenarios: too many assignees and missing assignees
        string memory testLabel2 = "testbadassignees";
        uint64 expires = uint64(block.timestamp + expiryDuration);

        // Scenario 1: Register with only some critical roles (missing ROLE_SET_SUBREGISTRY and admin roles)
        uint256 tokenId2 = ethRegistry.register(
            testLabel2,
            user,
            ethRegistry,
            address(0),
            RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER | RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN,
            expires
        );

        uint256 criticalRoles = RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER |
            RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER_ADMIN |
            RegistryRolesLib.ROLE_SET_SUBREGISTRY |
            RegistryRolesLib.ROLE_SET_SUBREGISTRY_ADMIN |
            RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN;
        bytes memory ejectionData = _createEjectionData(
            testLabel2,
            l1Owner,
            l1Subregistry,
            l1Resolver,
            expires,
            criticalRoles
        );

        // Should fail due to missing ROLE_SET_SUBREGISTRY and admin roles
        vm.expectRevert(
            abi.encodeWithSelector(
                L2BridgeController.TooManyRoleAssignees.selector,
                tokenId2,
                criticalRoles
            )
        );
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), tokenId2, 1, ejectionData);

        // Scenario 2: Grant the missing roles, then add extra assignees
        uint256 resource2 = ethRegistry.getResource(tokenId2);
        ethRegistry.grantRoles(resource2, RegistryRolesLib.ROLE_SET_SUBREGISTRY, user);
        address secondUser = address(0x999);
        ethRegistry.grantRoles(resource2, RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER, secondUser);

        // Get the current token ID after regeneration
        (uint256 currentTokenId, ) = ethRegistry.getNameData(testLabel2);

        // Should fail due to multiple assignees for ROLE_SET_TOKEN_OBSERVER
        vm.expectRevert(
            abi.encodeWithSelector(
                L2BridgeController.TooManyRoleAssignees.selector,
                currentTokenId,
                criticalRoles
            )
        );
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), currentTokenId, 1, ejectionData);
    }

    function test_eject_success_exactlyOneAssigneePerRole() public {
        // Test successful ejection when each critical role has exactly one assignee
        string memory testLabel3 = "testgoodassignees";
        uint64 expires = uint64(block.timestamp + expiryDuration);

        uint256 criticalRoles = RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER |
            RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER_ADMIN |
            RegistryRolesLib.ROLE_SET_SUBREGISTRY |
            RegistryRolesLib.ROLE_SET_SUBREGISTRY_ADMIN |
            RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN;
        uint256 tokenId3 = ethRegistry.register(
            testLabel3,
            user,
            ethRegistry,
            address(0),
            criticalRoles,
            expires
        );

        // Verify exactly one assignee per critical role
        (uint256 counts, uint256 mask) = ethRegistry.getAssigneeCount(tokenId3, criticalRoles);
        assertEq(
            counts & mask,
            criticalRoles,
            "Should have exactly one assignee for each critical role"
        );

        bytes memory ejectionData = _createEjectionData(
            testLabel3,
            l1Owner,
            l1Subregistry,
            l1Resolver,
            expires,
            criticalRoles
        );

        vm.recordLogs();
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), tokenId3, 1, ejectionData);

        // Verify successful ejection
        assertEq(
            ethRegistry.ownerOf(tokenId3),
            address(controller),
            "Token should be owned by controller after ejection"
        );
        assertEq(
            address(ethRegistry.getTokenObserver(tokenId3)),
            address(controller),
            "Token observer should be set to controller"
        );

        // Verify event emission
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == address(controller) &&
                logs[i].topics[0] == keccak256("NameEjectedToL1(bytes,uint256)")
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
        uint256 criticalRoles = RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER |
            RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER_ADMIN |
            RegistryRolesLib.ROLE_SET_SUBREGISTRY |
            RegistryRolesLib.ROLE_SET_SUBREGISTRY_ADMIN |
            RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN;
        uint256 tokenId4 = ethRegistry.register(
            testLabel4,
            user,
            ethRegistry,
            address(0),
            criticalRoles,
            expires
        );

        // Get the resource ID (this stays stable across regenerations)
        uint256 resourceId = ethRegistry.getResource(tokenId4);

        // Add multiple assignees to ROLE_SET_RESOLVER (this should not affect ejection)
        address user2 = address(0x666);
        address user3 = address(0x555);
        ethRegistry.grantRoles(resourceId, RegistryRolesLib.ROLE_SET_RESOLVER, user);
        ethRegistry.grantRoles(resourceId, RegistryRolesLib.ROLE_SET_RESOLVER, user2);
        ethRegistry.grantRoles(resourceId, RegistryRolesLib.ROLE_SET_RESOLVER, user3);

        // Get the current token ID after regeneration
        (uint256 currentTokenId, ) = ethRegistry.getNameData(testLabel4);

        bytes memory ejectionData = _createEjectionData(
            testLabel4,
            l1Owner,
            l1Subregistry,
            l1Resolver,
            expires,
            0
        );

        // Ejection should succeed despite multiple resolver role assignees
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), currentTokenId, 1, ejectionData);

        assertEq(
            ethRegistry.ownerOf(currentTokenId),
            address(controller),
            "Ejection should succeed"
        );
    }

    function test_Revert_ejectToL1_null_owner() public {
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint256 roleBitmap = RegistryRolesLib.ROLE_SET_RESOLVER |
            RegistryRolesLib.ROLE_SET_SUBREGISTRY |
            RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER |
            RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER_ADMIN |
            RegistryRolesLib.ROLE_SET_SUBREGISTRY_ADMIN |
            RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN;

        // Register a token for testing with a unique label
        string memory nullOwnerTestLabel = "nullOwnerTest";
        uint256 testTokenId = ethRegistry.register(
            nullOwnerTestLabel,
            user,
            ethRegistry,
            address(0),
            roleBitmap,
            expiryTime
        );

        // Setup ejection data with null owner
        address nullOwner = address(0);
        bytes memory ejectionData = _createEjectionData(
            nullOwnerTestLabel,
            nullOwner,
            l1Subregistry,
            l1Resolver,
            expiryTime,
            roleBitmap
        );

        // Transfer should revert due to null owner
        vm.expectRevert(abi.encodeWithSelector(InvalidOwner.selector));
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), testTokenId, 1, ejectionData);
    }

    function test_preMigration_directMint_noEjection() public {
        string memory preMigrationLabel = "premigrated";
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint256 roleBitmap = EACBaseRolesLib.ALL_ROLES;

        bridge.resetCounters();
        vm.recordLogs();

        uint256 preMigrationTokenId = ethRegistry.register(
            preMigrationLabel,
            address(controller),
            ethRegistry,
            address(0),
            roleBitmap,
            expiryTime
        );

        assertEq(
            ethRegistry.ownerOf(preMigrationTokenId),
            address(controller),
            "Controller should own the pre-migrated token"
        );

        assertEq(
            bridge.sendMessageCallCount(),
            0,
            "No bridge message should be sent on direct mint"
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 ejectionEventSig = keccak256("NameEjectedToL1(bytes,uint256)");
        for (uint256 i = 0; i < logs.length; i++) {
            assertFalse(
                logs[i].emitter == address(controller) && logs[i].topics[0] == ejectionEventSig,
                "NameEjectedToL1 should not be emitted on direct mint"
            );
        }

        assertEq(
            address(ethRegistry.getTokenObserver(preMigrationTokenId)),
            address(0),
            "Token observer should not be set on direct mint"
        );

        address subregAddr = datastore
            .getEntry(address(ethRegistry), preMigrationTokenId)
            .subregistry;
        assertEq(
            subregAddr,
            address(ethRegistry),
            "Subregistry should not be cleared on direct mint"
        );
    }

    function test_preMigration_mintThenTransfer_shouldEject() public {
        string memory mintThenTransferLabel = "minttransfer";
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint256 roleBitmap = RegistryRolesLib.ROLE_SET_RESOLVER |
            RegistryRolesLib.ROLE_SET_SUBREGISTRY |
            RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER |
            RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER_ADMIN |
            RegistryRolesLib.ROLE_SET_SUBREGISTRY_ADMIN |
            RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN;

        uint256 mintedTokenId = ethRegistry.register(
            mintThenTransferLabel,
            user,
            ethRegistry,
            address(0),
            roleBitmap,
            expiryTime
        );

        assertEq(
            ethRegistry.ownerOf(mintedTokenId),
            user,
            "User should own the newly minted token"
        );

        bytes memory ejectionData = _createEjectionData(
            mintThenTransferLabel,
            l1Owner,
            l1Subregistry,
            l1Resolver,
            expiryTime,
            roleBitmap
        );

        bridge.resetCounters();
        vm.recordLogs();

        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), mintedTokenId, 1, ejectionData);

        assertEq(
            ethRegistry.ownerOf(mintedTokenId),
            address(controller),
            "Controller should own the token after transfer"
        );

        assertEq(
            bridge.sendMessageCallCount(),
            1,
            "Bridge message should be sent after transfer from user"
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEjectionEvent = false;
        bytes32 ejectionEventSig = keccak256("NameEjectedToL1(bytes,uint256)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(controller) && logs[i].topics[0] == ejectionEventSig) {
                foundEjectionEvent = true;
                break;
            }
        }
        assertTrue(foundEjectionEvent, "NameEjectedToL1 should be emitted on transfer from user");

        assertEq(
            address(ethRegistry.getTokenObserver(mintedTokenId)),
            address(controller),
            "Token observer should be set after ejection"
        );

        address subregAddr = datastore.getEntry(address(ethRegistry), mintedTokenId).subregistry;
        assertEq(subregAddr, address(0), "Subregistry should be cleared after ejection");
    }

    function test_preMigration_directMintThenCompleteEjectionToL2() public {
        string memory preMigrationLabel = "premigrate2";
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint256 roleBitmap = RegistryRolesLib.ROLE_SET_RESOLVER |
            RegistryRolesLib.ROLE_SET_SUBREGISTRY |
            RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER |
            RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER_ADMIN |
            RegistryRolesLib.ROLE_SET_SUBREGISTRY_ADMIN |
            RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN;

        uint256 preMigrationTokenId = ethRegistry.register(
            preMigrationLabel,
            address(controller),
            ethRegistry,
            address(0),
            roleBitmap,
            expiryTime
        );

        assertEq(
            ethRegistry.ownerOf(preMigrationTokenId),
            address(controller),
            "Controller should own the pre-migrated token"
        );

        TransferData memory migrationData = TransferData({
            dnsEncodedName: LibLabel.dnsEncodeEthLabel(preMigrationLabel),
            owner: l2Owner,
            subregistry: l2Subregistry,
            resolver: l2Resolver,
            roleBitmap: roleBitmap,
            expires: 0
        });

        bridge.resetCounters();
        vm.recordLogs();

        vm.prank(address(bridge));
        controller.completeEjectionToL2(migrationData);

        assertEq(
            ethRegistry.ownerOf(preMigrationTokenId),
            l2Owner,
            "L2 owner should now own the token after migration"
        );

        address subregAddr = datastore
            .getEntry(address(ethRegistry), preMigrationTokenId)
            .subregistry;
        assertEq(
            subregAddr,
            l2Subregistry,
            "Subregistry should be set to L2 subregistry after migration"
        );

        address resolverAddr = ethRegistry.getResolver(preMigrationLabel);
        assertEq(resolverAddr, l2Resolver, "Resolver should be set to L2 resolver after migration");

        assertEq(
            address(ethRegistry.getTokenObserver(preMigrationTokenId)),
            address(0),
            "Token observer should be cleared after migration"
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEjectionEvent = false;
        bytes32 ejectionEventSig = keccak256("NameEjectedToL2(bytes,uint256)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(controller) && logs[i].topics[0] == ejectionEventSig) {
                foundEjectionEvent = true;
                break;
            }
        }
        assertTrue(foundEjectionEvent, "NameEjectedToL2 should be emitted on migration to L2");
    }
}
