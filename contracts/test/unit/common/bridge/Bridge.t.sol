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

contract BridgeTest is Test {
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

        // Deploy bridges with mock controller addresses
        l1Bridge = new L1Bridge(surgeBridge, L1_CHAIN_ID, L2_CHAIN_ID, mockL2Controller);
        l2Bridge = new L2Bridge(surgeBridge, L2_CHAIN_ID, L1_CHAIN_ID, mockL1Controller);
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
        assertEq(l1Bridge.sourceChainId(), L1_CHAIN_ID);
        assertEq(l1Bridge.destChainId(), L2_CHAIN_ID);
        assertEq(l1Bridge.bridgeController(), mockL2Controller);
    }

    function test_L2Bridge_ImmutableValues() public view {
        assertEq(address(l2Bridge.surgeBridge()), address(surgeBridge));
        assertEq(l2Bridge.sourceChainId(), L2_CHAIN_ID);
        assertEq(l2Bridge.destChainId(), L1_CHAIN_ID);
        assertEq(l2Bridge.bridgeController(), mockL1Controller);
    }
}
