// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IL1EjectionController} from "../L1/IL1EjectionController.sol";
import {MockBridgeHelper} from "./MockBridgeHelper.sol";

/**
 * @title MockL1Bridge
 * @dev Generic mock L1 bridge for testing cross-chain communication
 * Accepts arbitrary messages as bytes and calls the appropriate controller methods
 */
contract MockL1Bridge {
    // Event for outgoing messages from L1 to L2
    event L1ToL2Message(bytes message);
    
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
     * @dev Send a message from L1 to L2
     * In a real bridge, this would initiate cross-chain communication
     * For testing, it just emits an event that can be listened for
     */
    function sendMessageToL2(bytes calldata message) external {
        // Simply emit the message for testing purposes
        emit L1ToL2Message(message);
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
            string memory name;
            address l1Owner;
            address l1Subregistry;
            uint64 expiry;
            
            try MockBridgeHelper(bridgeHelper).decodeEjectionMessage(message) returns (
                string memory _name,
                address _l1Owner,
                address _l1Subregistry,
                uint64 _expiry
            ) {
                name = _name;
                l1Owner = _l1Owner;
                l1Subregistry = _l1Subregistry;
                expiry = _expiry;
                
                // Calculate the label hash directly from the name in the message
                uint256 labelHash = uint256(keccak256(abi.encodePacked(name)));
                
                // Call the complete ejection method on the controller
                IL1EjectionController(targetController).completeEjection(
                    labelHash,
                    l1Owner,
                    l1Subregistry,
                    0, // flags (not used in our simple implementation)
                    expiry,
                    "" // data (not used in our simple implementation)
                );
            } catch Error(string memory reason) {
                // Handle known errors
                revert(string(abi.encodePacked("L1Bridge decoding failed: ", reason)));
            } catch (bytes memory lowLevelData) {
                // Handle unknown errors
                revert("L1Bridge decoding failed with unknown error");
            }
        }
        
        // Emit event for tracking
        emit MessageProcessed(message);
    }
}