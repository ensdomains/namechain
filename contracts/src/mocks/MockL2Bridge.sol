// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IController.sol";

/**
 * @title MockL2Bridge
 * @dev Generic mock L2 bridge for testing cross-chain communication
 * Mirrors the L1 bridge functionality
 */
contract MockL2Bridge {
    // Event for outgoing messages from L2 to L1
    event L2ToL1Message(bytes message);
    
    // Event for message receipt acknowledgement
    event MessageProcessed(bytes message);

    // Target contract to call when receiving messages
    address public targetContract;
    
    constructor(address _targetContract) {
        targetContract = _targetContract;
    }
    
    function setTargetContract(address _targetContract) external {
        targetContract = _targetContract;
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
        // Call the specific process method on the target controller
        IController(targetContract).processMessage(message);
        
        // Emit event for tracking
        emit MessageProcessed(message);
    }
}
