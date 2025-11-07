// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ISurgeBridge, ISurgeBridgeMessageInvocable} from "~src/common/bridge/interfaces/ISurgeBridge.sol";

/**
 * @title MockSurgeBridge
 * @notice Mock implementation of Surge's ISurgeBridge interface for testing
 * @dev Simulates cross-chain message passing for unit and integration tests
 */
contract MockSurgeBridge is ISurgeBridge {
    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    mapping(bytes32 => Message) public messages;
    uint64 private _nextMessageId;

    ////////////////////////////////////////////////////////////////////////
    // ISurgeBridge Implementation
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Mock sendMessage that stores the message for later delivery
     * @param _message The message to send
     * @return msgHash_ The hash of the message
     * @return message_ The message with assigned ID
     */
    function sendMessage(Message calldata _message)
        external
        payable
        override
        returns (bytes32 msgHash_, Message memory message_)
    {
        // Assign message ID
        message_ = _message;
        message_.id = _nextMessageId++;
        message_.from = msg.sender;

        // Generate message hash
        msgHash_ = keccak256(abi.encode(message_));

        // Store message
        messages[msgHash_] = message_;

        emit MessageSent(msgHash_, message_);
    }

    /**
     * @notice Simulate message delivery by calling the target's onMessageInvocation
     * @param msgHash The hash of the message to deliver
     * @dev This simulates what the real Surge bridge would do on the destination chain
     */
    function deliverMessage(bytes32 msgHash) external {
        Message memory message = messages[msgHash];
        require(message.to != address(0), "Message not found");

        // Call the target contract's onMessageInvocation method
        ISurgeBridgeMessageInvocable(message.to).onMessageInvocation{value: message.value}(message.data);
    }

    /**
     * @notice Get the minimum gas limit required for a message
     * @param dataLength The length of the message data
     * @return The minimum gas limit
     */
    function getMessageMinGasLimit(uint256 dataLength) external pure returns (uint32) {
        // Simple calculation: base gas + gas per byte
        uint256 baseGas = 100000;
        uint256 gasPerByte = 16;
        uint256 totalGas = baseGas + (dataLength * gasPerByte);

        // Cap at uint32 max
        if (totalGas > type(uint32).max) {
            return type(uint32).max;
        }

        return uint32(totalGas);
    }

    ////////////////////////////////////////////////////////////////////////
    // Helper Methods for Testing
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Returns the next message ID
     * @return The next message ID
     */
    function nextMessageId() external view returns (uint64) {
        return _nextMessageId;
    }
}
