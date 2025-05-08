// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {MockL2EjectionController} from "./MockL2EjectionController.sol";
import {MockBridgeHelper} from "./MockBridgeHelper.sol";
import {TransferData} from "../common/EjectionController.sol";
import {IBridge} from "./IBridge.sol";  

/**
 * @title MockL2Bridge
 * @dev Generic mock L2 bridge for testing cross-chain communication
 * Accepts arbitrary messages as bytes and calls the appropriate controller methods
 */
contract MockL2Bridge is IBridge {
    // Event for outgoing messages from L2 to L1
    event L2ToL1Message(bytes message);
    
    // Event for message receipt acknowledgement
    event MessageProcessed(bytes message);

    // Target controller to call when receiving messages
    MockL2EjectionController public targetController;
    MockBridgeHelper public bridgeHelper;
    
    constructor(MockBridgeHelper _bridgeHelper) {
        bridgeHelper = _bridgeHelper;
    }
    
    function setTargetController(MockL2EjectionController _targetController) external {
        targetController = _targetController;
    }
    
    function sendMessageToL1(uint256 tokenId, TransferData memory transferData) external override {
        bytes memory message = bridgeHelper.encodeEjectionMessage(
            tokenId,
            transferData
        );

        // Simply emit the message for testing purposes
        emit L2ToL1Message(message);
    }

    function sendMessageToL2(uint256 /*tokenId*/, TransferData memory /*transferData*/) external pure override {
        revert("Not implemented");
    }    
    
    /**
     * @dev Simulate receiving a message from L1
     * Anyone can call this method with encoded message data
     */
    function receiveMessageFromL1(bytes calldata message) external {
        // Determine the message type and call the appropriate controller method
        bytes4 messageType = bytes4(message[:4]);
        
        if (messageType == bytes4(keccak256("NAME_MIGRATION"))) {
            try bridgeHelper.decodeEjectionMessage(message) returns (
                uint256 tokenId,
                TransferData memory _transferData
            ) {
                targetController.completeMigrationFromL1(tokenId, _transferData);
            } catch Error(string memory reason) {
                // Handle known errors
                revert(string(abi.encodePacked("L2Bridge decoding failed: ", reason)));
            } catch (bytes memory /*lowLevelData*/) {
                // Handle unknown errors
                revert("L2Bridge decoding failed with unknown error");
            }
        }
        
        // Emit event for tracking
        emit MessageProcessed(message);
    }
}