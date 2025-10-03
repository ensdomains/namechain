// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BridgeMessageType} from "../common/bridge/interfaces/IBridge.sol";
import {BridgeEncoderLib} from "../common/bridge/libraries/BridgeEncoderLib.sol";
import {TransferData} from "../common/bridge/types/TransferData.sol";
import {L2BridgeController} from "../L2/bridge/L2BridgeController.sol";

import {MockBridgeBase} from "./MockBridgeBase.sol";

/**
 * @title MockL2Bridge
 * @dev Generic mock L2 bridge for testing cross-chain communication
 * Accepts arbitrary messages as bytes and calls the appropriate controller methods
 */
contract MockL2Bridge is MockBridgeBase {
    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    // Bridge controller to call when receiving messages
    L2BridgeController public bridgeController;

    ////////////////////////////////////////////////////////////////////////
    // Events
    ////////////////////////////////////////////////////////////////////////

    // Type-specific events with tokenId and data
    event NameBridgedToL1(bytes message);

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    function setBridgeController(L2BridgeController bridgeController_) external {
        bridgeController = bridgeController_;
    }

    /**
     * @dev Send a message.
     */
    function sendMessage(bytes memory message) external override {
        BridgeMessageType messageType = BridgeEncoderLib.getMessageType(message);

        if (messageType == BridgeMessageType.EJECTION) {
            emit NameBridgedToL1(message);
        }
    }

    /**
     * @dev Handle ejection messages specific to L2 bridge
     */
    function _handleEjectionMessage(
        bytes memory /*dnsEncodedName*/,
        TransferData memory transferData
    ) internal override {
        bridgeController.completeEjectionToL2(transferData);
    }

    /**
     * @dev Handle renewal messages specific to L2 bridge
     */
    function _handleRenewalMessage(
        uint256 /*tokenId*/,
        uint64 /*newExpiry*/
    ) internal pure override {
        revert RenewalNotSupported();
    }
}
