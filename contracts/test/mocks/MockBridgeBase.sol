// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BridgeEncoderLib} from "~src/common/bridge/libraries/BridgeEncoderLib.sol";
import {AbstractBridgeController} from "~src/common/bridge/AbstractBridgeController.sol";
import {IBridge} from "~src/common/bridge/interfaces/IBridge.sol";
import {TransferData} from "~src/common/bridge/types/TransferData.sol";

/**
 * @title MockBridgeBase
 * @dev Abstract base class for mock bridge contracts
 * Contains common functionality for message encoding/decoding and event emission
 */
contract MockBridgeBase is IBridge {
    uint256 constant RING_SIZE = 256;

    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    AbstractBridgeController public bridgeController;
    MockBridgeBase public receiverBridge;
    mapping(uint256 => bytes) messages;
    uint256 public messageCount;

    ////////////////////////////////////////////////////////////////////////
    // Events
    ////////////////////////////////////////////////////////////////////////

    event MessageSent(bytes message);
    event MessageReceived(bytes message);

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    /// @dev Set the bridge controller on "this" side.
    function setBridgeController(AbstractBridgeController controller) external {
        bridgeController = controller;
    }

    /// @dev Set the bridge on the "other" side.
    function setReceiverBridge(MockBridgeBase bridge) external {
        receiverBridge = bridge;
    }

    /// @dev Return the last sent message.
    function lastMessage() external view returns (bytes memory) {
        return lastMessages(1)[0];
    }

    /// @dev Return the last sent messages.
    function lastMessages(uint256 n) public view returns (bytes[] memory msgs) {
        require(n <= RING_SIZE, "ring");
        require(n <= messageCount, "count");
        msgs = new bytes[](n);
        uint256 start = messageCount + RING_SIZE - n;
        for (uint256 i; i < n; ++i) {
            msgs[i] = messages[(start + i) % RING_SIZE];
        }
    }

    function sendMessage(bytes calldata message) external override {
        messages[messageCount++ % RING_SIZE] = message;
        emit MessageSent(message);
        if (address(receiverBridge) != address(0)) {
            receiverBridge.receiveMessage(message);
        }
    }

    /**
     * @dev Simulate receiving a message.
     * Anyone can call this method with encoded message data
     */
    function receiveMessage(bytes calldata message) external {
        BridgeEncoderLib.MessageType bmt = BridgeEncoderLib.getMessageType(message);
        emit MessageReceived(message);
        if (bmt == BridgeEncoderLib.MessageType.EJECTION) {
            TransferData memory td = BridgeEncoderLib.decodeEjection(message);
            bridgeController.completeEjection(td);
        } else if (bmt == BridgeEncoderLib.MessageType.RENEWAL) {
            (uint256 tokenId, uint64 newExpiry) = BridgeEncoderLib.decodeRenewal(message);
            _handleRenewalMessage(tokenId, newExpiry);
        }
    }

    /**
     * @dev Abstract method for handling renewal messages
     * Must be implemented by concrete bridge contracts
     */
    function _handleRenewalMessage(uint256 tokenId, uint64 newExpiry) internal virtual {}
}
