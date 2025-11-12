// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering, one-contract-per-file

import {Test, Vm} from "forge-std/Test.sol";

import {BridgeMessageType} from "~src/common/bridge/interfaces/IBridge.sol";
import {BridgeEncoderLib} from "~src/common/bridge/libraries/BridgeEncoderLib.sol";
import {TransferData} from "~src/common/bridge/types/TransferData.sol";
import {L1Bridge} from "~src/L1/bridge/L1Bridge.sol";
import {L2Bridge} from "~src/L2/bridge/L2Bridge.sol";
import {MockSurgeBridge} from "~test/mocks/MockSurgeBridge.sol";
import {ISurgeBridge} from "~src/common/bridge/interfaces/ISurgeBridge.sol";

contract BridgeTest is Test {
    address admin = address(this); // Test contract is the admin
    MockSurgeBridge surgeBridge;
    L1Bridge l1Bridge;
    L2Bridge l2Bridge;

    address mockL1Controller = address(0x1111);
    address mockL2Controller = address(0x2222);

    uint64 constant L1_CHAIN_ID = 1;
    uint64 constant L2_CHAIN_ID = 42;

    function setUp() public {
        // Deploy Surge bridge mock
        surgeBridge = new MockSurgeBridge();

        // Deploy bridges with surge bridge and controller addresses (admin is deployer by default)
        l1Bridge = new L1Bridge(surgeBridge, L1_CHAIN_ID, L2_CHAIN_ID, mockL2Controller);
        l2Bridge = new L2Bridge(surgeBridge, L2_CHAIN_ID, L1_CHAIN_ID, mockL1Controller);
        
        // Set up bridges with destination addresses
        // Test contract is admin by default since it deployed the bridges
        l1Bridge.setDestBridgeAddress(address(l2Bridge));
        l2Bridge.setDestBridgeAddress(address(l1Bridge));
    }

    function test_L1Bridge_SendMessage_EmitsEvent() public {
        bytes memory testData = hex"1234567890";

        vm.recordLogs();
        l1Bridge.sendMessage{value: 0.01 ether}(testData);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Verify MessageSent event from L1Bridge
        bool foundBridgeEvent = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("MessageSent(bytes)")) {
                foundBridgeEvent = true;
                break;
            }
        }
        assertTrue(foundBridgeEvent, "MessageSent event not emitted");
    }

    function test_L2Bridge_SendMessage_EmitsEvent() public {
        bytes memory testData = hex"abcdef";

        vm.recordLogs();
        l2Bridge.sendMessage{value: 0.005 ether}(testData);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Verify MessageSent event
        bool foundEvent = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("MessageSent(bytes)")) {
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "MessageSent event not emitted");
    }

    function test_L1Bridge_SendMessage_CallsSurgeBridge() public {
        bytes memory testData = hex"1234567890";

        uint64 msgIdBefore = surgeBridge.nextMessageId();

        l1Bridge.sendMessage{value: 0.01 ether}(testData);

        uint64 msgIdAfter = surgeBridge.nextMessageId();

        // Verify Surge bridge was called (message ID incremented)
        assertEq(msgIdAfter, msgIdBefore + 1, "Surge bridge not called");
    }

    function test_L1Bridge_OnMessageInvocation_OnlySurgeBridge() public {
        bytes memory testData = BridgeEncoderLib.encodeRenewal(123, uint64(block.timestamp + 86400));

        vm.expectRevert();
        vm.prank(address(0x9999));
        l1Bridge.onMessageInvocation(testData);
    }

    function test_L2Bridge_OnMessageInvocation_OnlySurgeBridge() public {
        TransferData memory transferData = TransferData({
            dnsEncodedName: hex"04746573740365746800",
            owner: address(0x1234),
            subregistry: address(0),
            resolver: address(0x5678),
            roleBitmap: 1,
            expires: uint64(block.timestamp + 86400)
        });
        bytes memory testData = BridgeEncoderLib.encodeEjection(transferData);

        vm.expectRevert();
        vm.prank(address(0x9999));
        l2Bridge.onMessageInvocation(testData);
    }

    function test_L2Bridge_OnMessageInvocation_RenewalNotSupported() public {
        bytes memory testData = BridgeEncoderLib.encodeRenewal(123, uint64(block.timestamp + 86400));

        vm.expectRevert();
        vm.prank(address(surgeBridge));
        l2Bridge.onMessageInvocation(testData);
    }

    function test_GasLimitCalculation() public view {
        bytes memory shortData = hex"1234";
        bytes memory longData = new bytes(10000);

        uint32 shortGasLimit = surgeBridge.getMessageMinGasLimit(shortData.length);
        uint32 longGasLimit = surgeBridge.getMessageMinGasLimit(longData.length);

        assertTrue(longGasLimit > shortGasLimit, "Gas limit should increase with data length");
    }

    function test_L1Bridge_ImmutableValues() public view {
        assertEq(address(l1Bridge.surgeBridge()), address(surgeBridge));
        assertEq(l1Bridge.SOURCE_CHAIN_ID(), L1_CHAIN_ID);
        assertEq(l1Bridge.DEST_CHAIN_ID(), L2_CHAIN_ID);
        assertEq(l1Bridge.BRIDGE_CONTROLLER(), mockL2Controller);
    }

    function test_L2Bridge_ImmutableValues() public view {
        assertEq(address(l2Bridge.surgeBridge()), address(surgeBridge));
        assertEq(l2Bridge.SOURCE_CHAIN_ID(), L2_CHAIN_ID);
        assertEq(l2Bridge.DEST_CHAIN_ID(), L1_CHAIN_ID);
        assertEq(l2Bridge.BRIDGE_CONTROLLER(), mockL1Controller);
    }

    // Access Control Tests
    
    function test_setSurgeBridge_OnlyAdmin() public {
        MockSurgeBridge newSurgeBridge = new MockSurgeBridge();
        
        // Should work for deployer (has admin role)
        vm.recordLogs();
        l1Bridge.setSurgeBridge(newSurgeBridge);
        
        // Verify event was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], keccak256("SurgeBridgeUpdated(address,address)"));
        
        // Verify address was updated
        assertEq(address(l1Bridge.surgeBridge()), address(newSurgeBridge));
    }
    
    function test_setSurgeBridge_RevertNonAdmin() public {
        MockSurgeBridge newSurgeBridge = new MockSurgeBridge();
        address nonAdmin = address(0x9999);
        
        vm.expectRevert();
        vm.prank(nonAdmin);
        l1Bridge.setSurgeBridge(newSurgeBridge);
    }
    
    function test_setDestBridgeAddress_OnlyAdmin() public {
        address newDestAddress = address(0x1234);
        
        // Should work for deployer (has admin role)
        vm.recordLogs();
        l1Bridge.setDestBridgeAddress(newDestAddress);
        
        // Verify event was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], keccak256("DestBridgeAddressUpdated(address,address)"));
        
        // Verify address was updated
        assertEq(l1Bridge.destBridgeAddress(), newDestAddress);
    }
    
    function test_setDestBridgeAddress_RevertNonAdmin() public {
        address newDestAddress = address(0x1234);
        address nonAdmin = address(0x9999);
        
        vm.expectRevert();
        vm.prank(nonAdmin);
        l1Bridge.setDestBridgeAddress(newDestAddress);
    }
    
    function test_sendMessage_RevertWhenSurgeBridgeNotSet() public {
        // Deploy a new bridge with zero address for surge bridge
        L1Bridge newBridge = new L1Bridge(ISurgeBridge(address(0)), L1_CHAIN_ID, L2_CHAIN_ID, mockL2Controller);
        newBridge.setDestBridgeAddress(address(l2Bridge));
        
        bytes memory testData = hex"1234567890";
        
        vm.expectRevert();
        newBridge.sendMessage{value: 0.01 ether}(testData);
    }
    
    function test_sendMessage_RevertWhenDestBridgeNotSet() public {
        // Deploy a new bridge without setting dest bridge
        L1Bridge newBridge = new L1Bridge(surgeBridge, L1_CHAIN_ID, L2_CHAIN_ID, mockL2Controller);
        
        bytes memory testData = hex"1234567890";
        
        vm.expectRevert();
        newBridge.sendMessage{value: 0.01 ether}(testData);
    }
    
    function test_sendMessage_WorksAfterProperSetup() public {
        bytes memory testData = hex"1234567890";
        
        // Should work after proper setup
        l1Bridge.sendMessage{value: 0.01 ether}(testData);
        
        // Verify message was sent (by checking surge bridge state)
        assertEq(surgeBridge.nextMessageId(), 1);
    }
    
    function test_adminCanSetMultipleValues() public {
        MockSurgeBridge newSurgeBridge = new MockSurgeBridge();
        address newDestAddress = address(0x1234);
        
        // Admin should be able to set both surge bridge and dest address
        l1Bridge.setSurgeBridge(newSurgeBridge);
        l1Bridge.setDestBridgeAddress(newDestAddress);
        
        assertEq(address(l1Bridge.surgeBridge()), address(newSurgeBridge));
        assertEq(l1Bridge.destBridgeAddress(), newDestAddress);
    }
}
