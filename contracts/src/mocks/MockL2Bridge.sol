// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {TransferData} from "../common/TransferData.sol";
import {MockL2EjectionController} from "./MockL2EjectionController.sol";
import {MockBaseBridge} from "./MockBaseBridge.sol";
import {BridgeMessageType, BridgeTarget, BridgeEncoder} from "../common/IBridge.sol";

/**
 * @title MockL2Bridge
 * @dev Generic mock L2 bridge for testing cross-chain communication
 * Accepts arbitrary messages as bytes and calls the appropriate controller methods
 */
contract MockL2Bridge is MockBaseBridge {
    // Ejection controller to call when receiving ejection messages
    MockL2EjectionController public ejectionController;
    
    // Custom errors
    error MigrationNotSupported();
    
    // Type-specific events with tokenId and data
    event NameEjectedToL1(uint256 indexed tokenId, bytes data);
    
    function setEjectionController(MockL2EjectionController _ejectionController) external {
        ejectionController = _ejectionController;
    }
    
    /**
     * @dev Send a message.
     */
    function sendMessage(BridgeTarget target, bytes memory message) external override {
        if (target != BridgeTarget.L1) {
            revert BridgeTargetNotSupported();
        }
        
        (BridgeMessageType messageType, uint256 tokenId, bytes memory data) = BridgeEncoder.decode(message);
        
        if (messageType == BridgeMessageType.MIGRATION) {
            // Migration messages are not supported in L2 bridge
            revert MigrationNotSupported();
        } else if (messageType == BridgeMessageType.EJECTION) {
            emit NameEjectedToL1(tokenId, data);
        }
    }
    
    /**
     * @dev Handle decoded messages specific to L2 bridge
     */
    function _handleDecodedMessage(
        BridgeMessageType messageType,
        uint256 tokenId,
        bytes memory data
    ) internal override {
        if (messageType == BridgeMessageType.EJECTION) {
            TransferData memory _transferData = abi.decode(data, (TransferData));
            ejectionController.completeMigrationFromL1(tokenId, _transferData);
        } else if (messageType == BridgeMessageType.MIGRATION) {
            // TODO: handle migration messages
        }
    }
}