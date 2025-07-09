// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {L2EjectionController} from "../L2/L2EjectionController.sol";
import {L2MigrationController} from "../L2/L2MigrationController.sol";
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
    L2EjectionController public ejectionController;
    
    // Migration controller to call when receiving migration messages
    L2MigrationController public migrationController;
        
    // Type-specific events with tokenId and data
    event NameBridgedToL1(bytes message);
        
    function setEjectionController(L2EjectionController _ejectionController) external {
        ejectionController = _ejectionController;
    }
    
    function setMigrationController(L2MigrationController _migrationController) external {
        migrationController = _migrationController;
    }
    
    /**
     * @dev Send a message.
     */
    function sendMessage(bytes memory message) external override {
        BridgeMessageType messageType = BridgeEncoder.getMessageType(message);
        
        if (messageType == BridgeMessageType.MIGRATION) {
            // Sending migration messages are not supported in L2 bridge
            revert MigrationNotSupported();
        } else if (messageType == BridgeMessageType.EJECTION) {
            emit NameBridgedToL1(message);
        }
    }
    
    /**
     * @dev Handle ejection messages specific to L2 bridge
     */
    function _handleEjectionMessage(
        bytes memory /*dnsEncodedName*/,
        TransferData memory transferData
    ) internal override {
        ejectionController.completeEjectionFromL1(transferData);
    }
    
    /**
     * @dev Handle migration messages specific to L2 bridge
     */
    function _handleMigrationMessage(
        bytes memory dnsEncodedName,
        MigrationData memory migrationData
    ) internal override {
        migrationController.completeMigrationFromL1(dnsEncodedName, migrationData);
    }
}