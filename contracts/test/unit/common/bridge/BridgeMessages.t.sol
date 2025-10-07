// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering, one-contract-per-file

import {Test, Vm} from "forge-std/Test.sol";

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

import {EACBaseRolesLib} from "~src/common/access-control/EnhancedAccessControl.sol";
import {BridgeMessageType} from "~src/common/bridge/interfaces/IBridge.sol";
import {BridgeEncoderLib} from "~src/common/bridge/libraries/BridgeEncoderLib.sol";
import {BridgeRolesLib} from "~src/common/bridge/libraries/BridgeRolesLib.sol";
import {TransferData} from "~src/common/bridge/types/TransferData.sol";
import {IRegistryMetadata} from "~src/common/registry/interfaces/IRegistryMetadata.sol";
import {PermissionedRegistry} from "~src/common/registry/PermissionedRegistry.sol";
import {RegistryDatastore} from "~src/common/registry/RegistryDatastore.sol";
import {L1BridgeController} from "~src/L1/bridge/L1BridgeController.sol";
import {L2BridgeController} from "~src/L2/bridge/L2BridgeController.sol";
import {MockBridgeBase} from "~test/mocks/MockBridgeBase.sol";
import {MockL1Bridge} from "~test/mocks/MockL1Bridge.sol";
import {MockL2Bridge} from "~test/mocks/MockL2Bridge.sol";

contract MockRegistryMetadata is IRegistryMetadata {
    function tokenUri(uint256) external pure override returns (string memory) {
        return "";
    }
}

contract BridgeMessagesTest is Test {
    MockL1Bridge l1Bridge;
    MockL2Bridge l2Bridge;
    L1BridgeController l1Controller;
    L2BridgeController l2Controller;
    PermissionedRegistry registry;
    RegistryDatastore datastore;
    MockRegistryMetadata registryMetadata;

    string testLabel = "test";
    address testOwner = address(0x1234);
    address testResolver = address(0x5678);
    uint64 testExpiry = uint64(block.timestamp + 86400);
    uint256 testRoleBitmap = EACBaseRolesLib.ALL_ROLES;

    function setUp() public {
        // Deploy dependencies
        datastore = new RegistryDatastore();
        registryMetadata = new MockRegistryMetadata();

        // Deploy registry
        registry = new PermissionedRegistry(
            datastore,
            registryMetadata,
            address(this),
            EACBaseRolesLib.ALL_ROLES
        );

        // Deploy bridges
        l1Bridge = new MockL1Bridge();
        l2Bridge = new MockL2Bridge();

        // link bridges
        l1Bridge.setReceiverBridge(l2Bridge);
        l2Bridge.setReceiverBridge(l1Bridge);

        // Deploy controllers
        l1Controller = new L1BridgeController(registry, l1Bridge);
        l2Controller = new L2BridgeController(l2Bridge, registry, datastore);

        // Set up bridge controllers
        l1Bridge.setBridgeController(l1Controller);
        l2Bridge.setBridgeController(l2Controller);

        // Grant necessary roles (filter out admin roles since they're restricted)
        uint256 regularRoles = EACBaseRolesLib.ALL_ROLES & ~EACBaseRolesLib.ADMIN_ROLES;
        registry.grantRootRoles(regularRoles, address(l1Controller));
        registry.grantRootRoles(regularRoles, address(l2Controller));

        // Grant bridge roles so the bridges can call the controllers
        l1Controller.grantRootRoles(BridgeRolesLib.ROLE_EJECTOR, address(l1Bridge));
        l2Controller.grantRootRoles(BridgeRolesLib.ROLE_EJECTOR, address(l2Bridge));
    }

    function test_encodeDecodeEjection() public view {
        TransferData memory transferData = TransferData({
            label: testLabel,
            owner: testOwner,
            subregistry: address(registry),
            resolver: testResolver,
            expiry: testExpiry,
            roleBitmap: testRoleBitmap
        });

        // Encode message
        bytes memory encodedMessage = BridgeEncoderLib.encodeEjection(transferData);

        // Verify message type
        BridgeMessageType messageType = BridgeEncoderLib.getMessageType(encodedMessage);
        assertEq(uint256(messageType), uint256(BridgeMessageType.EJECTION));

        // Decode message
        (TransferData memory decodedData) = BridgeEncoderLib.decodeEjection(encodedMessage);

        // Verify decoded data
        assertEq(keccak256(bytes(decodedData.label)), keccak256(bytes(testLabel)));
        assertEq(keccak256(bytes(decodedData.label)), keccak256(bytes(transferData.label)));
        assertEq(decodedData.owner, transferData.owner);
        assertEq(decodedData.subregistry, transferData.subregistry);
        assertEq(decodedData.resolver, transferData.resolver);
        assertEq(decodedData.expiry, transferData.expiry);
        assertEq(decodedData.roleBitmap, transferData.roleBitmap);
    }

    function test_encodeDecodeRenewal() public view {
        uint256 tokenId = 12345;
        uint64 newExpiry = uint64(block.timestamp + 86400);

        // Encode message
        bytes memory encodedMessage = BridgeEncoderLib.encodeRenewal(tokenId, newExpiry);

        // Verify message type
        BridgeMessageType messageType = BridgeEncoderLib.getMessageType(encodedMessage);
        assertEq(uint256(messageType), uint256(BridgeMessageType.RENEWAL));

        // Decode message
        (uint256 decodedTokenId, uint64 decodedExpiry) = BridgeEncoderLib.decodeRenewal(
            encodedMessage
        );

        // Verify decoded data
        assertEq(decodedTokenId, tokenId);
        assertEq(decodedExpiry, newExpiry);
    }

    function test_l1Bridge_handleRenewal() public {
        // First register a name to renew
        uint256 tokenId = registry.register(
            testLabel,
            testOwner,
            registry,
            testResolver,
            testRoleBitmap,
            testExpiry
        );

        uint64 newExpiry = uint64(block.timestamp + 86400 * 2);

        // Encode renewal message
        bytes memory message = BridgeEncoderLib.encodeRenewal(tokenId, newExpiry);

        vm.recordLogs();

        // Simulate receiving the message through the bridge
        l1Bridge.receiveMessage(message);

        // Verify the renewal was processed
        uint64 updatedExpiry = datastore.getEntry(address(registry), tokenId).expiry;
        assertEq(updatedExpiry, newExpiry, "Expiry should be updated");

        // Check for RenewalSynchronized event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        bytes32 eventSig = keccak256("RenewalSynchronized(uint256,uint64)");

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSig) {
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "RenewalSynchronized event should be emitted");
    }

    function test_l2Bridge_revertRenewal() public {
        uint256 tokenId = 12345;
        uint64 newExpiry = uint64(block.timestamp + 86400);

        // Encode renewal message
        bytes memory message = BridgeEncoderLib.encodeRenewal(tokenId, newExpiry);

        // L2 bridge should revert on renewal messages
        vm.expectRevert(MockBridgeBase.RenewalNotSupported.selector);
        l2Bridge.receiveMessage(message);
    }

    function test_l1Bridge_sendMessage() external {
        bytes memory message = abi.encode(BridgeMessageType.UNKNOWN, "test");
        vm.expectEmit(false, false, false, true);
        emit MockBridgeBase.MessageSent(message);
        vm.expectEmit(false, false, false, true);
        emit MockBridgeBase.MessageReceived(message);
        l1Bridge.sendMessage(message);
    }

    function test_l2Bridge_sendMessage() external {
        bytes memory message = abi.encode(BridgeMessageType.UNKNOWN, "test");
        vm.expectEmit(false, false, false, true);
        emit MockBridgeBase.MessageSent(message);
        vm.expectEmit(false, false, false, true);
        emit MockBridgeBase.MessageReceived(message);
        l2Bridge.sendMessage(message);
    }
}
