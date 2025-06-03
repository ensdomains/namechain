// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {TransferData, MigrationData} from "./TransferData.sol";


/**
 * @dev The target of a bridge message.
 */
enum BridgeTarget {
    L1,
    L2
}

/**
 * @dev Interface for the bridge contract.
 */
interface IBridge {
    function sendMessage(BridgeTarget target, bytes memory message) external;
    function receiveMessage(bytes memory message) external;
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
        uint256 tokenId,
        bytes memory data
    ) internal pure returns (bytes memory) {
        return abi.encode(uint(messageType), tokenId, data);
    }

    /**
     * @dev Decode a message.
     */
    function decode(bytes memory message) internal pure returns (
        BridgeMessageType messageType,
        uint256 tokenId,
        bytes memory data
    ) {
        uint _messageType;
        (_messageType, tokenId, data) = abi.decode(message, (uint, uint256, bytes));
        messageType = BridgeMessageType(_messageType);
    }
}
