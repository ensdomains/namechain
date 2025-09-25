// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IBridge, BridgeMessageType} from "./../common/bridge/interfaces/IBridge.sol";
import {BridgeEncoderLib} from "./../common/bridge/libraries/BridgeEncoderLib.sol";
import {TransferData} from "./../common/bridge/types/TransferData.sol";

/**
 * @title MockBridgeBase
 * @dev Abstract base class for mock bridge contracts
 * Contains common functionality for message encoding/decoding and event emission
 */
abstract contract MockBridgeBase is IBridge {
    // Event for message receipt acknowledgement
    event MessageProcessed(bytes message);

    // Custom errors
    error RenewalNotSupported();

    /**
     * @dev Simulate receiving a message.
     * Anyone can call this method with encoded message data
     */
    function receiveMessage(bytes calldata message) external {
        BridgeMessageType messageType = BridgeEncoderLib.getMessageType(message);

        if (messageType == BridgeMessageType.EJECTION) {
            (bytes memory dnsEncodedName, TransferData memory transferData) = BridgeEncoderLib
                .decodeEjection(message);
            _handleEjectionMessage(dnsEncodedName, transferData);
        } else if (messageType == BridgeMessageType.RENEWAL) {
            (uint256 tokenId, uint64 newExpiry) = BridgeEncoderLib.decodeRenewal(message);
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
    function _handleRenewalMessage(uint256 tokenId, uint64 newExpiry) internal virtual;
}
