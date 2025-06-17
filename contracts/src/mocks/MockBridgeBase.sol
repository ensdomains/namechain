// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {TransferData} from "../common/TransferData.sol";
import {IBridge, BridgeEncoder, BridgeMessageType} from "../common/IBridge.sol";

/**
 * @title MockBridgeBase
 * @dev Abstract base class for mock bridge contracts
 * Contains common functionality for message encoding/decoding and event emission
 */
abstract contract MockBridgeBase is IBridge {
    // Custom errors
    error MigrationNotSupported();
    
    // Event for message receipt acknowledgement
    event MessageProcessed(bytes message);
    
    /**
     * @dev Simulate receiving a message.
     * Anyone can call this method with encoded message data
     */
    function receiveMessage(bytes calldata message) external {
        (BridgeMessageType _messageType, bytes memory _dnsEncodedName, bytes memory _data) = BridgeEncoder.decode(message);
        _handleDecodedMessage(_messageType, _dnsEncodedName, _data);
        // Emit event for tracking
        emit MessageProcessed(message);
    }
    
    /**
     * @dev Abstract method for handling decoded messages
     * Must be implemented by concrete bridge contracts
     */
    function _handleDecodedMessage(
        BridgeMessageType messageType,
        bytes memory dnsEncodedName,
        bytes memory data
    ) internal virtual;
} 