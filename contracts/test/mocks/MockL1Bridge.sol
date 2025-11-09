// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {L1BridgeController} from "~src/L1/bridge/L1BridgeController.sol";

import {MockBridgeBase} from "./MockBridgeBase.sol";

/**
 * @title MockL1Bridge
 * @dev Generic mock L1-to-L2 bridge for testing cross-chain communication
 * Accepts arbitrary messages as bytes and calls the appropriate controller methods
 */
contract MockL1Bridge is MockBridgeBase {
    /**
     * @dev Handle renewal messages specific to L1 bridge
     */
    function _handleRenewalMessage(uint256 tokenId, uint64 newExpiry) internal override {
        L1BridgeController(address(bridgeController)).syncRenewal(tokenId, newExpiry);
    }
}
