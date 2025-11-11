// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Bridge} from "../../common/bridge/Bridge.sol";
import {ISurgeBridge} from "../../common/bridge/interfaces/ISurgeBridge.sol";
import {TransferData} from "../../common/bridge/types/TransferData.sol";

import {L1BridgeController} from "./L1BridgeController.sol";

/**
 * @title L1Bridge
 * @notice L1 bridge implementation that integrates with Surge bridge
 * @dev Handles ejections from L2 to L1 and renewal syncs from L2 to L1
 */
contract L1Bridge is Bridge {
    ////////////////////////////////////////////////////////////////////////
    // Constructor
    ////////////////////////////////////////////////////////////////////////

    constructor(
        ISurgeBridge surgeBridge_,
        uint64 l1ChainId_,
        uint64 l2ChainId_,
        address l1BridgeController_
    ) Bridge(surgeBridge_, l1ChainId_, l2ChainId_, l1BridgeController_) {}

    ////////////////////////////////////////////////////////////////////////
    // Internal Methods
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Handle ejection message from L2 to L1
     * @param transferData The transfer data for the ejection
     */
    function _handleEjectionMessage(
        bytes memory /*dnsEncodedName*/,
        TransferData memory transferData
    ) internal override {
        L1BridgeController(BRIDGE_CONTROLLER).completeEjectionToL1(transferData);
    }

    /**
     * @notice Handle renewal message from L2 to L1
     * @param tokenId The token ID being renewed
     * @param newExpiry The new expiry timestamp
     */
    function _handleRenewalMessage(uint256 tokenId, uint64 newExpiry) internal override {
        L1BridgeController(BRIDGE_CONTROLLER).syncRenewal(tokenId, newExpiry);
    }
}
