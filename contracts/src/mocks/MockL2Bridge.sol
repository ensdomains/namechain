// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {L2BridgeController} from "../L2/L2BridgeController.sol";
import {MockBridgeBase} from "./MockBridgeBase.sol";
import {BridgeMessageType} from "../common/IBridge.sol";
import {BridgeEncoder} from "../common/BridgeEncoder.sol";
import {TransferData} from "../common/TransferData.sol";

/**
 * @title MockL2Bridge
 * @dev Generic mock L2 bridge for testing cross-chain communication
 * Accepts arbitrary messages as bytes and calls the appropriate controller methods
 */
contract MockL2Bridge is MockBridgeBase {
    // Bridge controller to call when receiving messages
    L2BridgeController public bridgeController;

    // Type-specific events with tokenId and data
    event NameBridgedToL1(bytes message);

    function setBridgeController(L2BridgeController _bridgeController) external {
        bridgeController = _bridgeController;
    }

    /**
     * @dev Send a message.
     */
    function sendMessage(bytes memory message) external override {
        BridgeMessageType messageType = BridgeEncoder.getMessageType(message);

        if (messageType == BridgeMessageType.EJECTION) {
            emit NameBridgedToL1(message);
        }
    }

    /**
     * @dev Handle ejection messages specific to L2 bridge
     */
    function _handleEjectionMessage(bytes memory, /*dnsEncodedName*/ TransferData memory transferData)
        internal
        override
    {
        bridgeController.completeEjectionFromL1(transferData);
    }

    /**
     * @dev Handle renewal messages specific to L2 bridge
     */
    function _handleRenewalMessage(uint256, /*tokenId*/ uint64 /*newExpiry*/ ) internal pure override {
        revert RenewalNotSupported();
    }
}
