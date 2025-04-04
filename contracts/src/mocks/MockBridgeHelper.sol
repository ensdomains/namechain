// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title MockBridgeHelper
 * @dev Helper contract to encode/decode ENS-specific messages for the bridge
 * This helps interact with the generic bridge interfaces
 */
contract MockBridgeHelper {
    // Message types
    bytes4 constant NAME_EJECTION = bytes4(keccak256("NAME_EJECTION"));
    bytes4 constant NAME_MIGRATION = bytes4(keccak256("NAME_MIGRATION"));
    
    function encodeEjectionMessage(
        string calldata name,
        address l1Owner,
        address l1Subregistry,
        uint64 expiry
    ) external pure returns (bytes memory) {
        return abi.encode(
            NAME_EJECTION,
            name,
            l1Owner,
            l1Subregistry,
            expiry
        );
    }
    
    function encodeMigrationMessage(
        string calldata name,
        address l2Owner,
        address l2Subregistry
    ) external pure returns (bytes memory) {
        return abi.encode(
            NAME_MIGRATION,
            name,
            l2Owner,
            l2Subregistry
        );
    }
    
    function decodeEjectionMessage(bytes calldata message) external pure returns (
        string memory name,
        address l1Owner,
        address l1Subregistry,
        uint64 expiry
    ) {
        bytes4 messageType;
        (messageType, name, l1Owner, l1Subregistry, expiry) = abi.decode(
            message,
            (bytes4, string, address, address, uint64)
        );
        require(messageType == NAME_EJECTION, "Invalid message type");
    }
    
    function decodeMigrationMessage(bytes calldata message) external pure returns (
        string memory name,
        address l2Owner,
        address l2Subregistry
    ) {
        bytes4 messageType;
        (messageType, name, l2Owner, l2Subregistry) = abi.decode(
            message,
            (bytes4, string, address, address)
        );
        require(messageType == NAME_MIGRATION, "Invalid message type");
    }
}


