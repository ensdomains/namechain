// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {TransferData} from "./../common/TransferData.sol";
import {L2BridgeController} from "./../L2/L2BridgeController.sol";
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
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    function setBridgeController(L2BridgeController bridgeController_) external {
        bridgeController = bridgeController_;
    }

    /**
     * @dev Handle ejection messages specific to L2 bridge
     */
    function _handleEjectionMessage(TransferData memory transferData) internal override {
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
