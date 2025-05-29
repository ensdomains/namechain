// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {MockBridgeHelper} from "./MockBridgeHelper.sol";
import {TransferData} from "../common/EjectionController.sol";
import {MockL1EjectionController} from "./MockL1EjectionController.sol";
import {IBridge} from "./IBridge.sol";

/**
 * @title MockL1Bridge
 * @dev Generic mock L1 bridge for testing cross-chain communication
 * Accepts arbitrary messages as bytes and calls the appropriate controller methods
 */
contract MockL1Bridge is IBridge {
    // Event for outgoing messages from L1 to L2
    event L1ToL2Message(bytes message);
    
    // Event for message receipt acknowledgement
    event MessageProcessed(bytes message);

    // Target controller to call when receiving messages
    MockL1EjectionController public targetController;
    MockBridgeHelper public bridgeHelper;
    
    constructor(MockBridgeHelper _bridgeHelper) {
        bridgeHelper = _bridgeHelper;
    }
    
    function setTargetController(MockL1EjectionController _targetController) external {
        targetController = _targetController;
    }
    
    /**
     * @dev Send a message from L1 to L2
     * In a real bridge, this would initiate cross-chain communication
     * For testing, it just emits an event that can be listened for
     */
    function sendMessageToL2(uint256 tokenId, TransferData memory transferData) external override {
        bytes memory message = bridgeHelper.encodeEjectionMessage(
            tokenId,
            transferData
        );

        // Simply emit the message for testing purposes
        emit L1ToL2Message(message);
    }

    function sendMessageToL1(uint256 /*tokenId*/, TransferData memory /*transferData*/) external pure override {
        revert("Not implemented");
    }
    
    /**
     * @dev Simulate receiving a message from L2
     * Anyone can call this method with encoded message data
     */
    function receiveMessageFromL2(bytes calldata message) external {
        // Determine the message type and call the appropriate controller method
        bytes4 messageType = bytes4(message[:4]);
        
        if (messageType == bytes4(keccak256("NAME_EJECTION"))) {
            // Decode the ejection message
            try bridgeHelper.decodeEjectionMessage(message) returns (
                uint256 /*tokenId*/,
                TransferData memory _transferData
            ) {
                targetController.completeEjectionFromL2(_transferData);
            } catch Error(string memory reason) {
                // Handle known errors
                revert(string(abi.encodePacked("L1Bridge decoding failed: ", reason)));
            } catch (bytes memory /*lowLevelData*/) {
                // Handle unknown errors
                revert("L1Bridge decoding failed with unknown error");
            }
        }
        
        // Emit event for tracking
        emit MessageProcessed(message);
    }
}
