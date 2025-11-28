// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ISurgeNativeBridge} from "../../common/bridge/interfaces/ISurgeNativeBridge.sol";
import {SurgeBridge} from "../../common/bridge/SurgeBridge.sol";
import {TransferData} from "../../common/bridge/types/TransferData.sol";

import {L2BridgeController} from "./L2BridgeController.sol";

/**
 * @title L2SurgeBridge
 * @notice L2 bridge implementation that integrates with Surge bridge
 * @dev Handles ejections from L1 to L2. Renewals are not supported (they go L2→L1 only)
 */
contract L2SurgeBridge is SurgeBridge {
    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    address private immutable _BRIDGE_CONTROLLER;

    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    error RenewalNotSupported();

    ////////////////////////////////////////////////////////////////////////
    // Constructor
    ////////////////////////////////////////////////////////////////////////

    constructor(
        ISurgeNativeBridge surgeNativeBridge_,
        uint64 l2ChainId_,
        uint64 l1ChainId_,
        address l2BridgeController_
    ) SurgeBridge(surgeNativeBridge_, l2ChainId_, l1ChainId_) {
        _BRIDGE_CONTROLLER = l2BridgeController_;
    }

    ////////////////////////////////////////////////////////////////////////
    // Public Methods
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Get the bridge controller address
     * @return The address of the bridge controller
     */
    function bridgeControllerAddress() public view override returns (address) {
        return _BRIDGE_CONTROLLER;
    }

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
        L2BridgeController(bridgeControllerAddress()).completeEjectionToL2(transferData);
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
