// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Bridge} from "../../common/bridge/Bridge.sol";
import {ISurgeBridge} from "../../common/bridge/interfaces/ISurgeBridge.sol";
import {TransferData} from "../../common/bridge/types/TransferData.sol";

import {L2BridgeController} from "./L2BridgeController.sol";

/**
 * @title L2Bridge
 * @notice L2 bridge implementation that integrates with Surge bridge
 * @dev Handles ejections from L1 to L2. Renewals are not supported (they go L2→L1 only)
 */
contract L2Bridge is Bridge {
    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    error RenewalNotSupported();

    ////////////////////////////////////////////////////////////////////////
    // Constructor
    ////////////////////////////////////////////////////////////////////////

    constructor(
        ISurgeBridge surgeBridge_,
        uint64 l2ChainId_,
        uint64 l1ChainId_,
        address l2BridgeController_
    ) Bridge(surgeBridge_, l2ChainId_, l1ChainId_, l2BridgeController_) {}

    ////////////////////////////////////////////////////////////////////////
    // Internal Methods
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Handle ejection message from L1 to L2
     * @param transferData The transfer data for the ejection
     */
    function _handleEjectionMessage(
        bytes memory /*dnsEncodedName*/,
        TransferData memory transferData
    ) internal override {
        L2BridgeController(BRIDGE_CONTROLLER).completeEjectionToL2(transferData);
    }

    /**
     * @notice Handle renewal message - not supported on L2
     * @dev Renewals only flow from L2 to L1, never the reverse
     */
    function _handleRenewalMessage(
        uint256 /*tokenId*/,
        uint64 /*newExpiry*/
    ) internal pure override {
        revert RenewalNotSupported();
    }
}
