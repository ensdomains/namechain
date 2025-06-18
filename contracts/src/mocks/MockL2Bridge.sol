// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {MockL2EjectionController} from "./MockL2EjectionController.sol";
import {MockBridgeBase} from "./MockBridgeBase.sol";
import {BridgeMessageType} from "../common/IBridge.sol";
import {BridgeEncoder} from "../common/BridgeEncoder.sol";
import {TransferData, MigrationData} from "../common/TransferData.sol";

/**
 * @title MockL2Bridge
 * @dev Generic mock L2 bridge for testing cross-chain communication
 * Accepts arbitrary messages as bytes and calls the appropriate controller methods
 */
contract MockL2Bridge is MockBridgeBase {
    // Ejection controller to call when receiving ejection messages
    MockL2EjectionController public ejectionController;
        
    // Type-specific events with tokenId and data
    event NameEjectedToL1(bytes dnsEncodedName, bytes data);
    
    function setEjectionController(MockL2EjectionController _ejectionController) external {
        ejectionController = _ejectionController;
    }
    
    /**
     * @dev Send a message.
     */
    function sendMessage(bytes memory message) external override {
        BridgeMessageType messageType = BridgeEncoder.getMessageType(message);
        
        if (messageType == BridgeMessageType.MIGRATION) {
            // Migration messages are not supported in L2 bridge
            revert MigrationNotSupported();
        } else if (messageType == BridgeMessageType.EJECTION) {
            (bytes memory dnsEncodedName, TransferData memory transferData) = BridgeEncoder.decodeEjection(message);
            emit NameEjectedToL1(dnsEncodedName, abi.encode(transferData));
        }
    }
    
    /**
     * @dev Handle ejection messages specific to L2 bridge
     */
    function _handleEjectionMessage(
        bytes memory /*dnsEncodedName*/,
        TransferData memory transferData
    ) internal override {
        uint256 tokenId = uint256(keccak256(bytes(transferData.label)));
        ejectionController.completeMigrationFromL1(tokenId, transferData);
    }
    
    /**
     * @dev Handle migration messages specific to L2 bridge
     */
    function _handleMigrationMessage(
        bytes memory /*dnsEncodedName*/,
        MigrationData memory /*migrationData*/
    ) internal override {
        // TODO: handle migration messages
    }
}