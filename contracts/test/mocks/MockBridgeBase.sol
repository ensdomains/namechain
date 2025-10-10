// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IBridge, BridgeMessageType} from "~src/common/bridge/interfaces/IBridge.sol";
import {BridgeEncoderLib} from "~src/common/bridge/libraries/BridgeEncoderLib.sol";
import {TransferData} from "~src/common/bridge/types/TransferData.sol";

/**
 * @title MockBridgeBase
 * @dev Abstract base class for mock bridge contracts
 * Contains common functionality for message encoding/decoding and event emission
 */
abstract contract MockBridgeBase is IBridge {
    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    MockBridgeBase public receiverBridge;
    bytes public lastMessage;

    ////////////////////////////////////////////////////////////////////////
    // Events
    ////////////////////////////////////////////////////////////////////////

    // Event for message receipt acknowledgement
    event MessageSent(bytes message);
    event MessageReceived(bytes message);

    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    error RenewalNotSupported();

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    /// @dev Set the bridge on the "other" side.
    function setReceiverBridge(MockBridgeBase bridge) external {
        receiverBridge = bridge;
    }

    function sendMessage(bytes calldata message) external override {
        lastMessage = message;
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
        BridgeMessageType messageType = BridgeEncoderLib.getMessageType(message);
        emit MessageReceived(message);
        if (messageType == BridgeMessageType.EJECTION) {
            (TransferData memory transferData) = BridgeEncoderLib.decodeEjection(message);
            _handleEjectionMessage(transferData.dnsEncodedName, transferData);
        } else if (messageType == BridgeMessageType.RENEWAL) {
            (uint256 tokenId, uint64 newExpiry) = BridgeEncoderLib.decodeRenewal(message);
            _handleRenewalMessage(tokenId, newExpiry);
        }
    }

    /**
     * @dev Abstract method for handling ejection messages
     * Must be implemented by concrete bridge contracts
     */
    function _handleEjectionMessage(
        bytes memory dnsEncodedName,
        TransferData memory transferData
    ) internal virtual;

    /**
     * @dev Abstract method for handling renewal messages
     * Must be implemented by concrete bridge contracts
     */
    function _handleRenewalMessage(uint256 tokenId, uint64 newExpiry) internal virtual;
}
