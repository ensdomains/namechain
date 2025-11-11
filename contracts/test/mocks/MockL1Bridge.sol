// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ISurgeBridge} from "~src/common/bridge/interfaces/ISurgeBridge.sol";
import {BridgeMessageType} from "~src/common/bridge/interfaces/IBridge.sol";
import {BridgeEncoderLib} from "~src/common/bridge/libraries/BridgeEncoderLib.sol";
import {Bridge} from "~src/common/bridge/Bridge.sol";
import {TransferData} from "~src/common/bridge/types/TransferData.sol";
import {L1Bridge} from "~src/L1/bridge/L1Bridge.sol";
import {L1BridgeController} from "~src/L1/bridge/L1BridgeController.sol";

/**
 * @title MockL1Bridge
 * @notice Mock L1 bridge for testing that extends the real L1Bridge with failure simulation
 */
contract MockL1Bridge is L1Bridge {
    ////////////////////////////////////////////////////////////////////////
    // Failure Simulation Storage
    ////////////////////////////////////////////////////////////////////////

    bool public shouldFailOnSend;
    bool public shouldFailOnReceive;
    bytes4 public sendFailureReason;
    bytes4 public receiveFailureReason;
    string public customFailureMessage;

    ////////////////////////////////////////////////////////////////////////
    // Events for Testing
    ////////////////////////////////////////////////////////////////////////

    event MockFailureTriggered(string reason);

    ////////////////////////////////////////////////////////////////////////
    // Constructor
    ////////////////////////////////////////////////////////////////////////

    constructor(
        ISurgeBridge surgeBridge_,
        uint64 l1ChainId_,
        uint64 l2ChainId_,
        address l1BridgeController_
    ) L1Bridge(surgeBridge_, l1ChainId_, l2ChainId_, l1BridgeController_) {}

    ////////////////////////////////////////////////////////////////////////
    // Failure Simulation Methods
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Configure the bridge to fail on message sending
     * @param fail Whether to fail on send
     * @param reason The error selector to revert with
     * @param message Custom error message for generic failures
     */
    function setFailOnSend(bool fail, bytes4 reason, string memory message) external {
        shouldFailOnSend = fail;
        sendFailureReason = reason;
        customFailureMessage = message;
    }

    /**
     * @notice Configure the bridge to fail on message reception
     * @param fail Whether to fail on receive
     * @param reason The error selector to revert with
     * @param message Custom error message for generic failures
     */
    function setFailOnReceive(bool fail, bytes4 reason, string memory message) external {
        shouldFailOnReceive = fail;
        receiveFailureReason = reason;
        customFailureMessage = message;
    }

    /**
     * @notice Reset all failure flags
     */
    function resetFailures() external {
        shouldFailOnSend = false;
        shouldFailOnReceive = false;
        sendFailureReason = bytes4(0);
        receiveFailureReason = bytes4(0);
        customFailureMessage = "";
    }

    ////////////////////////////////////////////////////////////////////////
    // Overridden Bridge Methods
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Override sendMessage to simulate sending failures
     * @param message The message to send
     */
    function sendMessage(bytes calldata message) external payable override {
        if (shouldFailOnSend) {
            emit MockFailureTriggered("Send failure simulated");
            
            if (sendFailureReason == InsufficientFee.selector) {
                revert InsufficientFee(1 ether, msg.value);
            } else if (sendFailureReason != bytes4(0)) {
                // For custom error selectors, we'll revert with the custom message
                revert(customFailureMessage);
            } else {
                revert("Mock bridge send failure");
            }
        }
        
        // Implement the core bridge logic inline
        emit MessageSent(message);

        // Calculate required gas limit based on message data length
        uint32 gasLimit = surgeBridge.getMessageMinGasLimit(message.length);

        // Build Surge Message struct
        ISurgeBridge.Message memory surgeMessage = ISurgeBridge.Message({
            id: 0, // Auto-assigned by Surge bridge
            fee: uint64(msg.value), // Use provided ETH as fee
            gasLimit: gasLimit,
            from: address(0), // Auto-assigned by Surge bridge
            srcChainId: sourceChainId,
            srcOwner: msg.sender,
            destChainId: destChainId,
            destOwner: msg.sender,
            to: bridgeController, // Target is the bridge controller on destination chain
            value: 0,
            data: message
        });

        // Send message through Surge bridge
        surgeBridge.sendMessage{value: msg.value}(surgeMessage);
    }

    /**
     * @notice Override onMessageInvocation to simulate receiving failures
     * @param _data The message data
     */
    function onMessageInvocation(bytes calldata _data) external payable override {
        if (shouldFailOnReceive) {
            emit MockFailureTriggered("Receive failure simulated");
            
            if (receiveFailureReason == OnlySurgeBridge.selector) {
                revert OnlySurgeBridge();
            } else if (receiveFailureReason != bytes4(0)) {
                // For custom error selectors, we'll revert with the custom message
                revert(customFailureMessage);
            } else {
                revert("Mock bridge receive failure");
            }
        }
        
        // Implement the core bridge logic inline
        if (msg.sender != address(surgeBridge)) {
            revert OnlySurgeBridge();
        }

        emit MessageReceived(_data);

        // Decode message type and route to appropriate handler
        BridgeMessageType messageType = BridgeEncoderLib.getMessageType(_data);

        if (messageType == BridgeMessageType.EJECTION) {
            TransferData memory transferData = BridgeEncoderLib.decodeEjection(_data);
            _handleEjectionMessage(transferData.dnsEncodedName, transferData);
        } else if (messageType == BridgeMessageType.RENEWAL) {
            (uint256 tokenId, uint64 newExpiry) = BridgeEncoderLib.decodeRenewal(_data);
            _handleRenewalMessage(tokenId, newExpiry);
        }
    }

    ////////////////////////////////////////////////////////////////////////
    // Testing Helper Methods
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Get the bridge controller as L1BridgeController for easier testing
     * @return The L1BridgeController instance
     */
    function getBridgeController() external view returns (L1BridgeController) {
        return L1BridgeController(bridgeController);
    }

    /**
     * @notice Check if the bridge would fail on send with current settings
     * @return true if send would fail
     */
    function wouldFailOnSend() external view returns (bool) {
        return shouldFailOnSend;
    }

    /**
     * @notice Check if the bridge would fail on receive with current settings
     * @return true if receive would fail
     */
    function wouldFailOnReceive() external view returns (bool) {
        return shouldFailOnReceive;
    }
}