// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {L1BridgeController} from "../../src/L1/L1BridgeController.sol";
import {MockBridgeBase, TransferData} from "./MockBridgeBase.sol";
/**
 * @title MockL1Bridge
 * @dev Generic mock L1-to-L2 bridge for testing cross-chain communication
 * Accepts arbitrary messages as bytes and calls the appropriate controller methods
 */
contract MockL1Bridge is MockBridgeBase {
    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    // Bridge controller to call when receiving ejection messages
    L1BridgeController public bridgeController;

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    function setBridgeController(L1BridgeController bridgeController_) external {
        bridgeController = bridgeController_;
    }

    /**
     * @dev Handle ejection messages specific to L1 bridge
     */
    function _handleEjectionMessage(TransferData memory transferData) internal override {
        bridgeController.completeEjectionToL1(transferData);
    }

    /**
     * @dev Handle renewal messages specific to L1 bridge
     */
    function _handleRenewalMessage(uint256 tokenId, uint64 newExpiry) internal override {
        bridgeController.syncRenewal(tokenId, newExpiry);
    }
}
