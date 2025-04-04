// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IController.sol";

/**
 * @title MockL1Bridge
 * @dev Generic mock L1 bridge for testing cross-chain communication
 * Accepts arbitrary messages as bytes and simply emits events
 */
contract MockL1Bridge {
    // Event for outgoing messages from L1 to L2
    event L1ToL2Message(bytes message);
    
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
        // Call the specific process method on the target controller
        IController(targetContract).processMessage(message);
        
        // Emit event for tracking
        emit MessageProcessed(message);
    }
}
