// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BridgeMessageType} from "./IBridge.sol";
import {TransferData} from "./TransferData.sol";

/// @dev Library for encoding and decoding bridge messages.
library BridgeEncoder {
    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    /// @dev Error thrown when message type is invalid for ejection
    error InvalidEjectionMessageType();

    /// @dev Error thrown when message type is invalid for renewal
    error InvalidRenewalMessageType();

    error InvalideMessageType(BridgeMessageType messageType);
    error UnexpectedMessageType(uint256 ity);

    ////////////////////////////////////////////////////////////////////////
    // Library Functions
    ////////////////////////////////////////////////////////////////////////

    /// @dev Encode an ejection message.
    function encodeEjection(TransferData memory data) internal pure returns (bytes memory) {
        return abi.encode(BridgeMessageType.EJECTION, data);
    }

    /// @dev Decode an ejection message.
    function decodeEjection(bytes memory message) internal pure returns (TransferData memory data) {
        BridgeMessageType messageType;
        (messageType, data) = abi.decode(message, (BridgeMessageType, TransferData));
        if (messageType != BridgeMessageType.EJECTION) {
            revert InvalidEjectionMessageType();
        }
    }

    /// @dev Encode a renewal message.
    function encodeRenewal(uint256 tokenId, uint64 newExpiry) internal pure returns (bytes memory) {
        return abi.encode(BridgeMessageType.RENEWAL, tokenId, newExpiry);
    }

    /// @dev Decode a renewal message.
    function decodeRenewal(
        bytes memory message
    ) internal pure returns (uint256 tokenId, uint64 newExpiry) {
        BridgeMessageType messageType;
        (messageType, tokenId, newExpiry) = abi.decode(
            message,
            (BridgeMessageType, uint256, uint64)
        );
        if (messageType != BridgeMessageType.RENEWAL) {
            revert InvalidRenewalMessageType();
        }
    }

    /// @dev Helper function to get the message type from an encoded message.
    function getMessageType(bytes memory message) internal pure returns (BridgeMessageType) {
        uint256 ity = uint256(bytes32(message));
        return
            message.length < 32 || ity > uint256(type(BridgeMessageType).max)
                ? BridgeMessageType.UNKNOWN
                : BridgeMessageType(ity);
    }
}
