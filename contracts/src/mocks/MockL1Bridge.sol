// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {TransferData, MigrationData} from "../common/TransferData.sol";
import {MockL1EjectionController} from "./MockL1EjectionController.sol";
import {MockBaseBridge} from "./MockBaseBridge.sol";
import {BridgeMessageType, BridgeTarget, BridgeEncoder} from "../common/IBridge.sol";

/**
 * @title MockL1Bridge
 * @dev Generic mock L1-to-L2 bridge for testing cross-chain communication
 * Accepts arbitrary messages as bytes and calls the appropriate controller methods
 */
contract MockL1Bridge is MockBaseBridge {
    // Ejection controller to call when receiving ejection messages
    MockL1EjectionController public ejectionController;
    
    // Type-specific events with tokenId and data
    event NameEjectedToL2(uint256 indexed tokenId, bytes data);
    event NameMigratedToL2(uint256 indexed tokenId, bytes data);
    
    function setEjectionController(MockL1EjectionController _ejectionController) external {
        ejectionController = _ejectionController;
    }
    
    /**
     * @dev Override sendMessage to emit specific events based on message type
     */
    function sendMessage(BridgeTarget target, bytes memory message) external override {
        if (target != BridgeTarget.L2) {
            revert BridgeTargetNotSupported();
        }
        
        (BridgeMessageType messageType, uint256 tokenId, bytes memory data) = BridgeEncoder.decode(message);
        
        if (messageType == BridgeMessageType.EJECTION) {
            emit NameEjectedToL2(tokenId, data);
        } else if (messageType == BridgeMessageType.MIGRATION) {
            emit NameMigratedToL2(tokenId, data);
        }
    }
    
    /**
     * @dev Handle decoded messages specific to L1 bridge
     */
    function _handleDecodedMessage(
        BridgeMessageType messageType,
        uint256 /*tokenId*/,
        bytes memory data
    ) internal override {
        if (messageType == BridgeMessageType.EJECTION) {
            TransferData memory _transferData = abi.decode(data, (TransferData));
            ejectionController.completeEjectionFromL2(_transferData);
        } else if (messageType == BridgeMessageType.MIGRATION) {
            revert MigrationNotSupported();
        }
    }
}
