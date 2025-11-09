// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {TransferData} from "../types/TransferData.sol";

/// @dev Library for encoding and decoding bridge messages.
library BridgeEncoderLib {
    ////////////////////////////////////////////////////////////////////////
    // Types
    ////////////////////////////////////////////////////////////////////////

    enum MessageType {
        UNKNOWN,
        EJECTION,
        RENEWAL
    }

    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    //error InvalidMessageType(MessageType messageType);
    error UnexpectedMessageType(MessageType got, MessageType expect);

    ////////////////////////////////////////////////////////////////////////
    // Library Functions
    ////////////////////////////////////////////////////////////////////////

    /// @dev Encode an ejection message.
    function encodeEjection(TransferData memory td) internal pure returns (bytes memory) {
        return abi.encode(MessageType.EJECTION, td);
    }

    /// @dev Decode an ejection message.
    function decodeEjection(bytes memory message) internal pure returns (TransferData memory td) {
        MessageType messageType;
        (messageType, td) = abi.decode(message, (MessageType, TransferData));
        _requireMessageType(messageType, MessageType.EJECTION);
    }

    /// @dev Encode a renewal message.
    function encodeRenewal(uint256 tokenId, uint64 newExpiry) internal pure returns (bytes memory) {
        return abi.encode(MessageType.RENEWAL, tokenId, newExpiry);
    }

    /// @dev Decode a renewal message.
    function decodeRenewal(
        bytes memory message
    ) internal pure returns (uint256 tokenId, uint64 newExpiry) {
        MessageType messageType;
        (messageType, tokenId, newExpiry) = abi.decode(message, (MessageType, uint256, uint64));
        _requireMessageType(messageType, MessageType.RENEWAL);
    }

    function _requireMessageType(MessageType got, MessageType expect) internal pure {
        if (got != expect) {
            revert UnexpectedMessageType(got, expect);
        }
    }

    /// @dev Helper function to get the message type from an encoded message.
    function getMessageType(bytes memory message) internal pure returns (MessageType) {
        uint256 ity = uint256(bytes32(message));
        return
            message.length < 32 || ity > uint256(type(MessageType).max)
                ? MessageType.UNKNOWN
                : MessageType(ity);
    }
}
