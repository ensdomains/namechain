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
import {ISurgeNativeBridge} from "~src/common/bridge/interfaces/ISurgeNativeBridge.sol";
import {L1SurgeBridge} from "~src/L1/bridge/L1SurgeBridge.sol";
import {L2SurgeBridge} from "~src/L2/bridge/L2SurgeBridge.sol";
import {MockSurgeNativeBridge} from "~test/mocks/MockSurgeNativeBridge.sol";

contract MockRegistryMetadata is IRegistryMetadata {
    function tokenUri(uint256) external pure override returns (string memory) {
        return "";
    }
}

contract BridgeMessagesTest is Test {
    MockSurgeNativeBridge surgeNativeBridge;
    L1SurgeBridge l1SurgeBridge;
    L2SurgeBridge l2SurgeBridge;
    L1BridgeController l1Controller;
    L2BridgeController l2Controller;
    PermissionedRegistry registry;
    RegistryDatastore datastore;
    MockRegistryMetadata registryMetadata;

    // Chain IDs for testing
    uint64 constant L1_CHAIN_ID = 1;
    uint64 constant L2_CHAIN_ID = 42;

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

        // Deploy Surge bridge mock
        surgeNativeBridge = new MockSurgeNativeBridge();

        // Deploy placeholder bridges first (needed to create controllers)
        l1SurgeBridge = new L1SurgeBridge(surgeNativeBridge, L1_CHAIN_ID, L2_CHAIN_ID, L1BridgeController(address(0)));
        l2SurgeBridge = new L2SurgeBridge(surgeNativeBridge, L2_CHAIN_ID, L1_CHAIN_ID, L2BridgeController(address(0)));

        // Deploy controllers
        l1Controller = new L1BridgeController(registry, l1SurgeBridge);
        l2Controller = new L2BridgeController(l2SurgeBridge, registry, datastore);

        // Re-deploy bridges with correct controller references
        l1SurgeBridge = new L1SurgeBridge(surgeNativeBridge, L1_CHAIN_ID, L2_CHAIN_ID, l1Controller);
        l2SurgeBridge = new L2SurgeBridge(surgeNativeBridge, L2_CHAIN_ID, L1_CHAIN_ID, l2Controller);

        // Set up bridges with destination addresses
        l1SurgeBridge.setDestBridgeAddress(address(l2SurgeBridge));
        l2SurgeBridge.setDestBridgeAddress(address(l1SurgeBridge));

        // Grant necessary roles (filter out admin roles since they're restricted)
        uint256 regularRoles = EACBaseRolesLib.ALL_ROLES & ~EACBaseRolesLib.ADMIN_ROLES;
        registry.grantRootRoles(regularRoles, address(l1Controller));

        // Update controller bridge references
        l1Controller.grantRootRoles(BridgeRolesLib.ROLE_SET_BRIDGE, address(this));
        l2Controller.grantRootRoles(BridgeRolesLib.ROLE_SET_BRIDGE, address(this));
        l1Controller.setBridge(l1SurgeBridge);
        l2Controller.setBridge(l2SurgeBridge);

        // Grant registry roles to L2 controller too
        registry.grantRootRoles(regularRoles, address(l2Controller));

        // Grant bridge roles so the NEW bridges can call the controllers
        l1Controller.grantRootRoles(BridgeRolesLib.ROLE_EJECTOR, address(l1SurgeBridge));
        l2Controller.grantRootRoles(BridgeRolesLib.ROLE_EJECTOR, address(l2SurgeBridge));

        // Fund the controllers for bridge operations
        vm.deal(address(l1Controller), 10 ether);
        vm.deal(address(l2Controller), 10 ether);
    }

    function test_encodeDecodeEjection() public view {
        bytes memory dnsEncodedName = NameCoder.ethName(testLabel);
        TransferData memory transferData = TransferData({
            dnsEncodedName: dnsEncodedName,
            owner: testOwner,
            subregistry: address(registry),
            resolver: testResolver,
            expires: testExpiry,
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
        assertEq(keccak256(decodedData.dnsEncodedName), keccak256(dnsEncodedName));
        assertEq(keccak256(decodedData.dnsEncodedName), keccak256(transferData.dnsEncodedName));
        assertEq(decodedData.owner, transferData.owner);
        assertEq(decodedData.subregistry, transferData.subregistry);
        assertEq(decodedData.resolver, transferData.resolver);
        assertEq(decodedData.expires, transferData.expires);
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

    function test_l1SurgeBridge_handleRenewal() public {
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
        bytes memory renewalMessage = BridgeEncoderLib.encodeRenewal(tokenId, newExpiry);

        vm.recordLogs();

        // Simulate receiving the message through Surge bridge
        ISurgeNativeBridge.Message memory surgeMessage = ISurgeNativeBridge.Message({
            id: 0,
            fee: 0,
            gasLimit: surgeNativeBridge.getMessageMinGasLimit(renewalMessage.length),
            from: address(l2SurgeBridge),
            srcChainId: L2_CHAIN_ID,
            srcOwner: address(this),
            destChainId: L1_CHAIN_ID,
            destOwner: address(this),
            to: address(l1SurgeBridge),
            value: 0,
            data: renewalMessage
        });

        (, ISurgeNativeBridge.Message memory sentMessage) = surgeNativeBridge.sendMessage(surgeMessage);
        surgeNativeBridge.deliverMessage(sentMessage);

        // Verify the renewal was processed
        uint64 updatedExpiry = registry.getExpiry(tokenId);
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

    function test_l2SurgeBridge_revertRenewal() public {
        uint256 tokenId = 12345;
        uint64 newExpiry = uint64(block.timestamp + 86400);

        // Encode renewal message
        bytes memory renewalMessage = BridgeEncoderLib.encodeRenewal(tokenId, newExpiry);

        // L2 bridge should revert on renewal messages with RenewalNotSupported

        // Simulate receiving renewal message on L2 bridge (should revert)
        ISurgeNativeBridge.Message memory surgeMessage = ISurgeNativeBridge.Message({
            id: 0,
            fee: 0,
            gasLimit: surgeNativeBridge.getMessageMinGasLimit(renewalMessage.length),
            from: address(l1SurgeBridge),
            srcChainId: L1_CHAIN_ID,
            srcOwner: address(this),
            destChainId: L2_CHAIN_ID,
            destOwner: address(this),
            to: address(l2SurgeBridge),
            value: 0,
            data: renewalMessage
        });

        (, ISurgeNativeBridge.Message memory sentMessage) = surgeNativeBridge.sendMessage(surgeMessage);

        // L2 bridge should revert on renewal messages with RenewalNotSupported
        vm.expectRevert(L2SurgeBridge.RenewalNotSupported.selector);
        surgeNativeBridge.deliverMessage(sentMessage);
    }

    function test_l1SurgeBridge_sendMessage() public {
        bytes memory testMessage = "test message";

        vm.recordLogs();
        vm.prank(address(l1Controller));
        l1SurgeBridge.sendMessage(testMessage);

        // Check for MessageSent event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        bytes32 eventSig = keccak256("MessageSent(bytes)");

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSig) {
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "MessageSent event should be emitted");
    }

    function test_l2SurgeBridge_sendMessage_ejection() public {
        bytes memory dnsEncodedName = NameCoder.ethName(testLabel);
        bytes memory ejectionMessage = BridgeEncoderLib.encodeEjection(
            TransferData({
                dnsEncodedName: dnsEncodedName,
                owner: testOwner,
                subregistry: address(registry),
                resolver: testResolver,
                expires: testExpiry,
                roleBitmap: testRoleBitmap
            })
        );

        vm.recordLogs();
        vm.prank(address(l2Controller));
        l2SurgeBridge.sendMessage(ejectionMessage);

        // Check for MessageSent event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        bytes32 eventSig = keccak256("MessageSent(bytes)");

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSig) {
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "MessageSent event should be emitted");
    }
}
