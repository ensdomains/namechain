// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {TransferData} from "./../common/TransferData.sol";
import {L1EjectionController} from "./../L1/L1EjectionController.sol";
import {MockBridgeBase} from "./MockBridgeBase.sol";

/**
 * @title MockL1Bridge
 * @dev Generic mock L1-to-L2 bridge for testing cross-chain communication
 * Accepts arbitrary messages as bytes and calls the appropriate controller methods
 */
contract MockL1Bridge is MockBridgeBase {
    // Ejection controller to call when receiving ejection messages
    L1EjectionController public ejectionController;

    event NameBridgedToL2(bytes message);

    function setEjectionController(L1EjectionController ejectionController_) external {
        ejectionController = ejectionController_;
    }

    /**
     * @dev Override sendMessage to emit specific events based on message type
     */
    function sendMessage(bytes memory message) external override {
        emit NameBridgedToL2(message);
    }

    /**
     * @dev Handle ejection messages specific to L1 bridge
     */
    function _handleEjectionMessage(
        bytes memory /*dnsEncodedName*/,
        TransferData memory transferData
    ) internal override {
        ejectionController.completeEjectionFromL2(transferData);
    }

    /**
     * @dev Handle renewal messages specific to L1 bridge
     */
    function _handleRenewalMessage(uint256 tokenId, uint64 newExpiry) internal override {
        ejectionController.syncRenewal(tokenId, newExpiry);
    }
}
