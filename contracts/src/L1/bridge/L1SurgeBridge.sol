// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ISurgeNativeBridge} from "../../common/bridge/interfaces/ISurgeNativeBridge.sol";
import {SurgeBridge} from "../../common/bridge/SurgeBridge.sol";
import {TransferData} from "../../common/bridge/types/TransferData.sol";

import {L1BridgeController} from "./L1BridgeController.sol";

/**
 * @title L1SurgeBridge
 * @notice L1 bridge implementation that integrates with Surge bridge
 * @dev Handles ejections from L2 to L1 and renewal syncs from L2 to L1
 */
contract L1SurgeBridge is SurgeBridge {
    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    address private immutable _BRIDGE_CONTROLLER;

    ////////////////////////////////////////////////////////////////////////
    // Constructor
    ////////////////////////////////////////////////////////////////////////

    constructor(
        ISurgeNativeBridge surgeNativeBridge_,
        uint64 l1ChainId_,
        uint64 l2ChainId_,
        address l1BridgeController_
    ) SurgeBridge(surgeNativeBridge_, l1ChainId_, l2ChainId_) {
        _BRIDGE_CONTROLLER = l1BridgeController_;
    }

    ////////////////////////////////////////////////////////////////////////
    // Public Methods
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Get the bridge controller address
     * @return The address of the bridge controller
     */
    function bridgeController() public view override returns (address) {
        return _BRIDGE_CONTROLLER;
    }

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
        L1BridgeController(bridgeController()).completeEjectionToL1(transferData);
    }

    /**
     * @notice Handle renewal message from L2 to L1
     * @param tokenId The token ID being renewed
     * @param newExpiry The new expiry timestamp
     */
    function _handleRenewalMessage(uint256 tokenId, uint64 newExpiry) internal override {
        L1BridgeController(bridgeController()).syncRenewal(tokenId, newExpiry);
    }
}
