// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {TransferData} from "../common/EjectionController.sol";

/**
 * @title MockBridgeHelper
 * @dev Helper contract to encode/decode ENS-specific messages for the bridge
 * This helps interact with the generic bridge interfaces
 */
contract MockBridgeHelper {
    // Message types
    bytes4 constant NAME_EJECTION = bytes4(keccak256("NAME_EJECTION"));
    
    function encodeEjectionMessage(
        uint256 tokenId,
        TransferData memory transferData
    ) external pure returns (bytes memory) {
        return abi.encode(
            NAME_EJECTION,
            tokenId,
            transferData
        );
    }
    
    function decodeEjectionMessage(bytes calldata message) external pure returns (
        uint256 tokenId,
        TransferData memory transferData
    ) {
        bytes4 messageType;
        (messageType, tokenId, transferData) = abi.decode(
            message,
            (bytes4, uint256, TransferData)
        );
        require(messageType == NAME_EJECTION, "Invalid message type");
    }
}


