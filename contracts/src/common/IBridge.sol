// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {TransferData, MigrationData} from "./TransferData.sol";


/**
 * @dev Interface for the bridge contract.
 */
interface IBridge {
    function sendMessage(bytes memory message) external;
}


/**
 * @dev The type of message being sent.
 */
enum BridgeMessageType {
    MIGRATION,
    EJECTION
}


/**
 * @dev Library for encoding and decoding bridge messages.
 */
library BridgeEncoder {
    /**
     * @dev Encode a message.
     */
    function encode(
        BridgeMessageType messageType,
        bytes memory dnsEncodedName,
        bytes memory data
    ) internal pure returns (bytes memory) {
        return abi.encode(uint(messageType), dnsEncodedName, data);
    }

    /**
     * @dev Decode a message.
     */
    function decode(bytes memory message) internal pure returns (
        BridgeMessageType messageType,
        bytes memory dnsEncodedName,
        bytes memory data
    ) {
        uint _messageType;
        (_messageType, dnsEncodedName, data) = abi.decode(message, (uint, bytes, bytes));
        messageType = BridgeMessageType(_messageType);
    }
}
