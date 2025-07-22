// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {TransferData, MigrationData} from "../common/TransferData.sol";
import {IBridge, BridgeMessageType} from "../common/IBridge.sol";
import {BridgeEncoder} from "../common/BridgeEncoder.sol";

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
        BridgeMessageType messageType = BridgeEncoder.getMessageType(message);

        if (messageType == BridgeMessageType.EJECTION) {
            (bytes memory dnsEncodedName, TransferData memory transferData) = BridgeEncoder.decodeEjection(message);
            _handleEjectionMessage(dnsEncodedName, transferData);
        } else if (messageType == BridgeMessageType.MIGRATION) {
            (bytes memory dnsEncodedName, MigrationData memory migrationData) = BridgeEncoder.decodeMigration(message);
            _handleMigrationMessage(dnsEncodedName, migrationData);
        }

        // Emit event for tracking
        emit MessageProcessed(message);
    }

    /**
     * @dev Abstract method for handling ejection messages
     * Must be implemented by concrete bridge contracts
     */
    function _handleEjectionMessage(bytes memory dnsEncodedName, TransferData memory transferData) internal virtual;

    /**
     * @dev Abstract method for handling migration messages
     * Must be implemented by concrete bridge contracts
     */
    function _handleMigrationMessage(bytes memory dnsEncodedName, MigrationData memory migrationData)
        internal
        virtual;
}
