// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BridgeMessageType} from "./IBridge.sol";
import {TransferData, MigrationData} from "./TransferData.sol";

/**
 * @dev Library for encoding and decoding bridge messages.
 */
library BridgeEncoder {
    /// @dev Error thrown when message type is invalid for migration
    error InvalidMigrationMessageType();
    
    /// @dev Error thrown when message type is invalid for ejection
    error InvalidEjectionMessageType();

    /**
     * @dev Encode a migration message.
     */
    function encodeMigration(
        bytes memory dnsEncodedName,
        MigrationData memory data
    ) internal pure returns (bytes memory) {
        return abi.encode(uint(BridgeMessageType.MIGRATION), dnsEncodedName, data);
    }

    /**
     * @dev Decode a migration message.
     */
    function decodeMigration(bytes memory message) internal pure returns (
        bytes memory dnsEncodedName,
        MigrationData memory data
    ) {
        uint _messageType;
        (_messageType, dnsEncodedName, data) = abi.decode(message, (uint, bytes, MigrationData));
        if (_messageType != uint(BridgeMessageType.MIGRATION)) {
            revert InvalidMigrationMessageType();
        }
    }

    /**
     * @dev Encode an ejection message.
     */
    function encodeEjection(
        bytes memory dnsEncodedName,
        TransferData memory data
    ) internal pure returns (bytes memory) {
        return abi.encode(uint(BridgeMessageType.EJECTION), dnsEncodedName, data);
    }

    /**
     * @dev Decode an ejection message.
     */
    function decodeEjection(bytes memory message) internal pure returns (
        bytes memory dnsEncodedName,
        TransferData memory data
    ) {
        uint _messageType;
        (_messageType, dnsEncodedName, data) = abi.decode(message, (uint, bytes, TransferData));
        if (_messageType != uint(BridgeMessageType.EJECTION)) {
            revert InvalidEjectionMessageType();
        }
    }

    /**
     * @dev Helper function to get the message type from an encoded message.
     */
    function getMessageType(bytes memory message) internal pure returns (BridgeMessageType) {
        uint _messageType = abi.decode(message, (uint));
        return BridgeMessageType(_messageType);
    }
}
