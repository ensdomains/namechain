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
        ISurgeBridge _surgeBridge,
        uint64 _l1ChainId,
        uint64 _l2ChainId,
        address _l1BridgeController
    ) Bridge(_surgeBridge, _l1ChainId, _l2ChainId, _l1BridgeController) {}

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
        L1BridgeController(bridgeController).completeEjectionToL1(transferData);
    }

    /**
     * @notice Handle renewal message from L2 to L1
     * @param tokenId The token ID being renewed
     * @param newExpiry The new expiry timestamp
     */
    function _handleRenewalMessage(uint256 tokenId, uint64 newExpiry) internal override {
        L1BridgeController(bridgeController).syncRenewal(tokenId, newExpiry);
    }
}
