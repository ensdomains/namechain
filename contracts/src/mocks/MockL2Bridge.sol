// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IL2EjectionController} from "../controller/IL2EjectionController.sol";
import {MockBridgeHelper} from "./MockBridgeHelper.sol";

/**
 * @title MockL2Bridge
 * @dev Generic mock L2 bridge for testing cross-chain communication
 * Accepts arbitrary messages as bytes and calls the appropriate controller methods
 */
contract MockL2Bridge {
    // Event for outgoing messages from L2 to L1
    event L2ToL1Message(bytes message);
    
    // Event for message receipt acknowledgement
    event MessageProcessed(bytes message);

    // Target controller to call when receiving messages
    address public targetController;
    address public bridgeHelper;
    
    constructor(address _targetController, address _bridgeHelper) {
        targetController = _targetController;
        bridgeHelper = _bridgeHelper;
    }
    
    function setTargetController(address _targetController) external {
        targetController = _targetController;
    }
    
    /**
     * @dev Send a message from L2 to L1
     * In a real bridge, this would initiate cross-chain communication
     * For testing, it just emits an event
     */
    function sendMessageToL1(bytes calldata message) external {
        // Simply emit the message for testing purposes
        emit L2ToL1Message(message);
    }
    
    /**
     * @dev Simulate receiving a message from L1
     * Anyone can call this method with encoded message data
     */
    function receiveMessageFromL1(bytes calldata message) external {
        // Determine the message type and call the appropriate controller method
        bytes4 messageType = bytes4(message[:4]);
        
        if (messageType == bytes4(keccak256("NAME_MIGRATION"))) {
            // Decode the migration message
            string memory name;
            address l2Owner;
            address l2Subregistry;
            
            try MockBridgeHelper(bridgeHelper).decodeMigrationMessage(message) returns (
                string memory _name,
                address _l2Owner,
                address _l2Subregistry
            ) {
                name = _name;
                l2Owner = _l2Owner;
                l2Subregistry = _l2Subregistry;
                
                // Calculate the label hash directly from the name in the message
                uint256 labelHash = uint256(keccak256(abi.encodePacked(name)));
                
                // Call the complete migration method on the controller
                IL2EjectionController(targetController).completeMigration(
                    labelHash,
                    l2Owner,
                    l2Subregistry,
                    "" // data (not used in our simple implementation)
                );
            } catch Error(string memory reason) {
                // Handle known errors
                revert(string(abi.encodePacked("L2Bridge decoding failed: ", reason)));
            } catch (bytes memory lowLevelData) {
                // Handle unknown errors
                revert("L2Bridge decoding failed with unknown error");
            }
        }
        
        // Emit event for tracking
        emit MessageProcessed(message);
    }
}