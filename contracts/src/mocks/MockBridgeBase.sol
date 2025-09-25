// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {TransferData} from "../common/TransferData.sol";
import {IBridge, BridgeMessageType} from "../common/IBridge.sol";
import {BridgeEncoder} from "../common/BridgeEncoder.sol";

/**
 * @title MockBridgeBase
 * @dev Abstract base class for mock bridge contracts
 * Contains common functionality for message encoding/decoding and event emission
 */
abstract contract MockBridgeBase is IBridge {
    // Custom errors
    error RenewalNotSupported();
    
    // Event for message receipt acknowledgement
    event MessageProcessed(bytes message);
    
    /**
     * @dev Simulate receiving a message.
     * Anyone can call this method with encoded message data
     */
    function receiveMessage(bytes calldata message) external {
        BridgeMessageType messageType = BridgeEncoder.getMessageType(message);

        if (messageType == BridgeMessageType.EJECTION) {
            (TransferData memory transferData) = BridgeEncoder.decodeEjection(message);
            _handleEjectionMessage(transferData.dnsEncodedName, transferData);
        } else if (messageType == BridgeMessageType.RENEWAL) {
            (uint256 tokenId, uint64 newExpiry) = BridgeEncoder.decodeRenewal(message);
            _handleRenewalMessage(tokenId, newExpiry);
        }
        
        // Emit event for tracking
        emit MessageProcessed(message);
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
    function _handleRenewalMessage(
        uint256 tokenId,
        uint64 newExpiry
    ) internal virtual;
} 