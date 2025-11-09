// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {MockBridgeBase} from "./MockBridgeBase.sol";

/**
 * @title MockL2Bridge
 * @dev Generic mock L2 bridge for testing cross-chain communication
 * Accepts arbitrary messages as bytes and calls the appropriate controller methods
 */
contract MockL2Bridge is MockBridgeBase {
    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    error RenewalNotSupported();

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    function _handleRenewalMessage(
        uint256 /*tokenId*/,
        uint64 /*newExpiry*/
    ) internal pure override {
        revert RenewalNotSupported();
    }
}
