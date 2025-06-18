// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {MockL1EjectionController} from "./MockL1EjectionController.sol";
import {MockBridgeBase} from "./MockBridgeBase.sol";
import {BridgeMessageType} from "../common/IBridge.sol";
import {BridgeEncoder} from "../common/BridgeEncoder.sol";
import {TransferData, MigrationData} from "../common/TransferData.sol";

/**
 * @title MockL1Bridge
 * @dev Generic mock L1-to-L2 bridge for testing cross-chain communication
 * Accepts arbitrary messages as bytes and calls the appropriate controller methods
 */
contract MockL1Bridge is MockBridgeBase {
    // Ejection controller to call when receiving ejection messages
    MockL1EjectionController public ejectionController;
    
    // Type-specific events with tokenId and data
    event NameEjectedToL2(bytes dnsEncodedName, bytes data);
    event NameMigratedToL2(bytes dnsEncodedName, bytes data);
    
    function setEjectionController(MockL1EjectionController _ejectionController) external {
        ejectionController = _ejectionController;
    }
    
    /**
     * @dev Override sendMessage to emit specific events based on message type
     */
    function sendMessage(bytes memory message) external override {
        BridgeMessageType messageType = BridgeEncoder.getMessageType(message);
        
        if (messageType == BridgeMessageType.EJECTION) {
            (bytes memory dnsEncodedName, TransferData memory transferData) = BridgeEncoder.decodeEjection(message);
            emit NameEjectedToL2(dnsEncodedName, abi.encode(transferData));
        } else if (messageType == BridgeMessageType.MIGRATION) {
            (bytes memory dnsEncodedName, MigrationData memory migrationData) = BridgeEncoder.decodeMigration(message);
            emit NameMigratedToL2(dnsEncodedName, abi.encode(migrationData));
        }
    }
    
    /**
     * @dev Handle ejection messages specific to L1 bridge
     */
    function _handleEjectionMessage(
        bytes memory /*dnsEncodedName*/,
        TransferData memory transferData
    ) internal override {
        ejectionController.completeEjectionFromL2(transferData);
    }
    
    /**
     * @dev Handle migration messages specific to L1 bridge
     */
    function _handleMigrationMessage(
        bytes memory /*dnsEncodedName*/,
        MigrationData memory /*migrationData*/
    ) pure internal override {
        revert MigrationNotSupported();
    }
}
