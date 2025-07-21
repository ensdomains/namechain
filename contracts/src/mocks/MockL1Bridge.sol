// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {L1EjectionController} from "../L1/L1EjectionController.sol";
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
    L1EjectionController public ejectionController;
    
    event NameBridgedToL2(bytes message);
    
    function setEjectionController(L1EjectionController _ejectionController) external {
        ejectionController = _ejectionController;
    }
    
    /**
     * @dev Override sendMessage to emit specific events based on message type
     */
    function sendMessage(bytes memory message) external override {
        emit NameBridgedToL2(message);
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

    /**
     * @dev Handle renewal messages specific to L1 bridge
     */
    function _handleRenewalMessage(
        uint256 tokenId,
        uint64 newExpiry
    ) internal override {
        ejectionController.syncRenewal(tokenId, newExpiry);
    }
}
