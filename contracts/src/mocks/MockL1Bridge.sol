// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {MockL1EjectionController} from "./MockL1EjectionController.sol";
import {MockBridgeBase} from "./MockBridgeBase.sol";
import {BridgeMessageType, BridgeEncoder} from "../common/IBridge.sol";

/**
 * @title MockL1Bridge
 * @dev Generic mock L1-to-L2 bridge for testing cross-chain communication
 * Accepts arbitrary messages as bytes and calls the appropriate controller methods
 */
contract MockL1Bridge is MockBridgeBase {
    // Ejection controller to call when receiving ejection messages
    MockL1EjectionController public ejectionController;
    
    // Type-specific events with tokenId and data
    event NameEjectedToL2(bytes indexed dnsEncodedName, bytes data);
    event NameMigratedToL2(bytes indexed dnsEncodedName, bytes data);
    
    function setEjectionController(MockL1EjectionController _ejectionController) external {
        ejectionController = _ejectionController;
    }
    
    /**
     * @dev Override sendMessage to emit specific events based on message type
     */
    function sendMessage(bytes memory message) external override {
        (BridgeMessageType messageType, bytes memory dnsEncodedName, bytes memory data) = BridgeEncoder.decode(message);
        
        if (messageType == BridgeMessageType.EJECTION) {
            emit NameEjectedToL2(dnsEncodedName, data);
        } else if (messageType == BridgeMessageType.MIGRATION) {
            emit NameMigratedToL2(dnsEncodedName, data);
        }
    }
    
    /**
     * @dev Handle decoded messages specific to L1 bridge
     */
    function _handleDecodedMessage(
        BridgeMessageType messageType,
        bytes memory /*dnsEncodedName*/,
        bytes memory data
    ) internal override {
        if (messageType == BridgeMessageType.EJECTION) {
            ejectionController.completeEjectionFromL2(data);
        } else if (messageType == BridgeMessageType.MIGRATION) {
            revert MigrationNotSupported();
        }
    }
}
