// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BridgeMessageType} from "../interfaces/IBridge.sol";
import {TransferData} from "../types/TransferData.sol";

/// @dev Library for encoding and decoding bridge messages.
library BridgeEncoderLib {
    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    /// @dev Error thrown when message type is invalid for ejection
    error InvalidEjectionMessageType();

    /// @dev Error thrown when message type is invalid for renewal
    error InvalidRenewalMessageType();

    ////////////////////////////////////////////////////////////////////////
    // Library Functions
    ////////////////////////////////////////////////////////////////////////

    /// @dev Encode an ejection message.
    function encodeEjection(TransferData memory data) internal pure returns (bytes memory) {
        return abi.encode(uint256(BridgeMessageType.EJECTION), data);
    }

    /// @dev Decode an ejection message.
    function decodeEjection(bytes memory message) internal pure returns (TransferData memory data) {
        uint256 _messageType;
        (_messageType, data) = abi.decode(message, (uint256, TransferData));
        if (_messageType != uint256(BridgeMessageType.EJECTION)) {
            revert InvalidEjectionMessageType();
        }
    }

    /// @dev Encode a renewal message.
    function encodeRenewal(uint256 tokenId, uint64 newExpiry) internal pure returns (bytes memory) {
        return abi.encode(uint256(BridgeMessageType.RENEWAL), tokenId, newExpiry);
    }

    /// @dev Decode a renewal message.
    function decodeRenewal(
        bytes memory message
    ) internal pure returns (uint256 tokenId, uint64 newExpiry) {
        uint256 _messageType;
        (_messageType, tokenId, newExpiry) = abi.decode(message, (uint256, uint256, uint64));
        if (_messageType != uint256(BridgeMessageType.RENEWAL)) {
            revert InvalidRenewalMessageType();
        }
    }

    /// @dev Helper function to get the message type from an encoded message.
    function getMessageType(bytes memory message) internal pure returns (BridgeMessageType) {
        uint256 _messageType = abi.decode(message, (uint256));
        return BridgeMessageType(_messageType);
    }
}
