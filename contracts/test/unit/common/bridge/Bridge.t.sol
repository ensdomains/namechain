// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering, one-contract-per-file

import {Test, Vm} from "forge-std/Test.sol";

import {BridgeMessageType} from "~src/common/bridge/interfaces/IBridge.sol";
import {BridgeEncoderLib} from "~src/common/bridge/libraries/BridgeEncoderLib.sol";
import {TransferData} from "~src/common/bridge/types/TransferData.sol";
import {L1BridgeController} from "~src/L1/bridge/L1BridgeController.sol";
import {L2BridgeController} from "~src/L2/bridge/L2BridgeController.sol";
import {L1SurgeBridge} from "~src/L1/bridge/L1SurgeBridge.sol";
import {L2SurgeBridge} from "~src/L2/bridge/L2SurgeBridge.sol";
import {MockSurgeNativeBridge} from "~test/mocks/MockSurgeNativeBridge.sol";
import {ISurgeNativeBridge} from "~src/common/bridge/interfaces/ISurgeNativeBridge.sol";

contract BridgeTest is Test {
    address admin = address(this); // Test contract is the admin
    MockSurgeNativeBridge surgeNativeBridge;
    L1SurgeBridge l1SurgeBridge;
    L2SurgeBridge l2SurgeBridge;

    address mockL1Controller = address(0x1111);
    address mockL2Controller = address(0x2222);

    uint64 constant L1_CHAIN_ID = 1;
    uint64 constant L2_CHAIN_ID = 42;

    function setUp() public {
        // Deploy Surge bridge mock
        surgeNativeBridge = new MockSurgeNativeBridge();

        // Deploy bridges with surge bridge and mock controller addresses (admin is deployer by default)
        l1SurgeBridge = new L1SurgeBridge(surgeNativeBridge, L1_CHAIN_ID, L2_CHAIN_ID, L1BridgeController(mockL2Controller));
        l2SurgeBridge = new L2SurgeBridge(surgeNativeBridge, L2_CHAIN_ID, L1_CHAIN_ID, L2BridgeController(mockL1Controller));

        // Set up bridges with destination addresses
        // Test contract is admin by default since it deployed the bridges
        l1SurgeBridge.setDestBridgeAddress(address(l2SurgeBridge));
        l2SurgeBridge.setDestBridgeAddress(address(l1SurgeBridge));

        // Fund the mock controllers with ETH for testing
        vm.deal(mockL2Controller, 10 ether);
        vm.deal(mockL1Controller, 10 ether);
    }

    function test_L1SurgeBridge_SendMessage_EmitsEvent() public {
        bytes memory testData = hex"1234567890";

        vm.recordLogs();
        vm.prank(mockL2Controller);
        l1SurgeBridge.sendMessage{value: 0.01 ether}(testData);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Verify MessageSent event from L1SurgeBridge
        bool foundBridgeEvent = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("MessageSent(bytes)")) {
                foundBridgeEvent = true;
                break;
            }
        }
        assertTrue(foundBridgeEvent, "MessageSent event not emitted");
    }

    function test_L2SurgeBridge_SendMessage_EmitsEvent() public {
        bytes memory testData = hex"abcdef";

        vm.recordLogs();
        vm.prank(mockL1Controller);
        l2SurgeBridge.sendMessage{value: 0.005 ether}(testData);

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

    function test_L1SurgeBridge_SendMessage_CallsSurgeBridge() public {
        bytes memory testData = hex"1234567890";

        uint64 msgIdBefore = surgeNativeBridge.nextMessageId();

        vm.prank(mockL2Controller);
        l1SurgeBridge.sendMessage{value: 0.01 ether}(testData);

        uint64 msgIdAfter = surgeNativeBridge.nextMessageId();

        // Verify Surge bridge was called (message ID incremented)
        assertEq(msgIdAfter, msgIdBefore + 1, "Surge bridge not called");
    }

    function test_L1SurgeBridge_OnMessageInvocation_OnlySurgeBridge() public {
        bytes memory testData = BridgeEncoderLib.encodeRenewal(123, uint64(block.timestamp + 86400));

        vm.expectRevert();
        vm.prank(address(0x9999));
        l1SurgeBridge.onMessageInvocation(testData);
    }

    function test_L2SurgeBridge_OnMessageInvocation_OnlySurgeBridge() public {
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
        l2SurgeBridge.onMessageInvocation(testData);
    }

    function test_L2SurgeBridge_OnMessageInvocation_RenewalNotSupported() public {
        bytes memory testData = BridgeEncoderLib.encodeRenewal(123, uint64(block.timestamp + 86400));

        vm.expectRevert();
        vm.prank(address(surgeNativeBridge));
        l2SurgeBridge.onMessageInvocation(testData);
    }

    function test_GasLimitCalculation() public view {
        bytes memory shortData = hex"1234";
        bytes memory longData = new bytes(10000);

        uint32 shortGasLimit = surgeNativeBridge.getMessageMinGasLimit(shortData.length);
        uint32 longGasLimit = surgeNativeBridge.getMessageMinGasLimit(longData.length);

        assertTrue(longGasLimit > shortGasLimit, "Gas limit should increase with data length");
    }

    function test_L1SurgeBridge_ImmutableValues() public view {
        assertEq(address(l1SurgeBridge.surgeNativeBridge()), address(surgeNativeBridge));
        assertEq(l1SurgeBridge.SOURCE_CHAIN_ID(), L1_CHAIN_ID);
        assertEq(l1SurgeBridge.DEST_CHAIN_ID(), L2_CHAIN_ID);
        assertEq(l1SurgeBridge.bridgeController(), mockL2Controller);
    }

    function test_L2SurgeBridge_ImmutableValues() public view {
        assertEq(address(l2SurgeBridge.surgeNativeBridge()), address(surgeNativeBridge));
        assertEq(l2SurgeBridge.SOURCE_CHAIN_ID(), L2_CHAIN_ID);
        assertEq(l2SurgeBridge.DEST_CHAIN_ID(), L1_CHAIN_ID);
        assertEq(l2SurgeBridge.bridgeController(), mockL1Controller);
    }

    // Access Control Tests
    
    function test_setSurgeNativeBridge_OnlyAdmin() public {
        MockSurgeNativeBridge newSurgeBridge = new MockSurgeNativeBridge();
        
        // Should work for deployer (has admin role)
        vm.recordLogs();
        l1SurgeBridge.setSurgeNativeBridge(newSurgeBridge);
        
        // Verify event was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], keccak256("SurgeNativeBridgeUpdated(address,address)"));
        
        // Verify address was updated
        assertEq(address(l1SurgeBridge.surgeNativeBridge()), address(newSurgeBridge));
    }
    
    function test_setSurgeNativeBridge_RevertNonAdmin() public {
        MockSurgeNativeBridge newSurgeBridge = new MockSurgeNativeBridge();
        address nonAdmin = address(0x9999);
        
        vm.expectRevert();
        vm.prank(nonAdmin);
        l1SurgeBridge.setSurgeNativeBridge(newSurgeBridge);
    }
    
    function test_setDestBridgeAddress_OnlyAdmin() public {
        address newDestAddress = address(0x1234);
        
        // Should work for deployer (has admin role)
        vm.recordLogs();
        l1SurgeBridge.setDestBridgeAddress(newDestAddress);
        
        // Verify event was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], keccak256("DestBridgeAddressUpdated(address,address)"));
        
        // Verify address was updated
        assertEq(l1SurgeBridge.destBridgeAddress(), newDestAddress);
    }
    
    function test_setDestBridgeAddress_RevertNonAdmin() public {
        address newDestAddress = address(0x1234);
        address nonAdmin = address(0x9999);
        
        vm.expectRevert();
        vm.prank(nonAdmin);
        l1SurgeBridge.setDestBridgeAddress(newDestAddress);
    }
    
    function test_sendMessage_RevertWhenDestBridgeNotSet() public {
        // Deploy a new bridge without setting dest bridge
        L1SurgeBridge newBridge = new L1SurgeBridge(surgeNativeBridge, L1_CHAIN_ID, L2_CHAIN_ID, L1BridgeController(mockL2Controller));
        
        bytes memory testData = hex"1234567890";
        
        vm.expectRevert();
        vm.prank(mockL2Controller);
        newBridge.sendMessage{value: 0.01 ether}(testData);
    }
    
    function test_sendMessage_WorksAfterProperSetup() public {
        bytes memory testData = hex"1234567890";
        
        // Should work after proper setup
        vm.prank(mockL2Controller);
        l1SurgeBridge.sendMessage{value: 0.01 ether}(testData);
        
        // Verify message was sent (by checking surge bridge state)
        assertEq(surgeNativeBridge.nextMessageId(), 1);
    }
    
    function test_adminCanSetMultipleValues() public {
        MockSurgeNativeBridge newSurgeBridge = new MockSurgeNativeBridge();
        address newDestAddress = address(0x1234);
        
        // Admin should be able to set both surge bridge and dest address
        l1SurgeBridge.setSurgeNativeBridge(newSurgeBridge);
        l1SurgeBridge.setDestBridgeAddress(newDestAddress);
        
        assertEq(address(l1SurgeBridge.surgeNativeBridge()), address(newSurgeBridge));
        assertEq(l1SurgeBridge.destBridgeAddress(), newDestAddress);
    }

    // New access control tests for sendMessage
    function test_sendMessage_OnlyBridgeController() public {
        bytes memory testData = hex"1234567890";
        
        // Should work when called by bridge controller
        vm.prank(mockL2Controller);
        l1SurgeBridge.sendMessage{value: 0.01 ether}(testData);
        
        assertEq(surgeNativeBridge.nextMessageId(), 1);
    }
    
    function test_sendMessage_RevertNonBridgeController() public {
        bytes memory testData = hex"1234567890";
        address nonController = address(0x9999);
        vm.deal(nonController, 1 ether);
        
        // Should revert when called by non-controller
        vm.expectRevert();
        vm.prank(nonController);
        l1SurgeBridge.sendMessage{value: 0.01 ether}(testData);
    }
    
    function test_L2SurgeBridge_sendMessage_OnlyBridgeController() public {
        bytes memory testData = hex"abcdef";
        
        // Should work when called by bridge controller
        vm.prank(mockL1Controller);
        l2SurgeBridge.sendMessage{value: 0.005 ether}(testData);
        
        assertEq(surgeNativeBridge.nextMessageId(), 1);
    }
    
    function test_L2SurgeBridge_sendMessage_RevertNonBridgeController() public {
        bytes memory testData = hex"abcdef";
        address nonController = address(0x9999);
        vm.deal(nonController, 1 ether);
        
        // Should revert when called by non-controller
        vm.expectRevert();
        vm.prank(nonController);
        l2SurgeBridge.sendMessage{value: 0.005 ether}(testData);
    }

    // New tests for getMinGasLimit method
    function test_getMinGasLimit_L1SurgeBridge() public view {
        bytes memory shortData = hex"1234";
        bytes memory longData = new bytes(1000);
        
        uint32 shortGasLimit = l1SurgeBridge.getMinGasLimit(shortData);
        uint32 longGasLimit = l1SurgeBridge.getMinGasLimit(longData);
        
        assertTrue(longGasLimit > shortGasLimit, "Gas limit should increase with data length");
        
        // Verify it matches the expected calculation
        uint32 expectedShortGas = surgeNativeBridge.getMessageMinGasLimit(shortData.length);
        uint32 expectedLongGas = surgeNativeBridge.getMessageMinGasLimit(longData.length);
        
        assertEq(shortGasLimit, expectedShortGas, "Short gas limit should match surge bridge calculation");
        assertEq(longGasLimit, expectedLongGas, "Long gas limit should match surge bridge calculation");
    }
    
    function test_getMinGasLimit_L2SurgeBridge() public view {
        bytes memory testData = hex"abcdef123456";
        
        uint32 gasLimit = l2SurgeBridge.getMinGasLimit(testData);
        uint32 expectedGas = surgeNativeBridge.getMessageMinGasLimit(testData.length);
        
        assertEq(gasLimit, expectedGas, "Gas limit should match surge bridge calculation");
    }
    
    function test_getMinGasLimit_EmptyData() public view {
        bytes memory emptyData = "";
        
        uint32 gasLimit = l1SurgeBridge.getMinGasLimit(emptyData);
        uint32 expectedGas = surgeNativeBridge.getMessageMinGasLimit(0);
        
        assertEq(gasLimit, expectedGas, "Gas limit should handle empty data correctly");
        assertTrue(gasLimit > 0, "Gas limit should be greater than zero even for empty data");
    }
}
