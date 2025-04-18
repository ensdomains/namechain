// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IL1EjectionController} from "../L1/IL1EjectionController.sol";
import {L1ETHRegistry} from "../L1/L1ETHRegistry.sol";

contract MockEjectionController is IL1EjectionController {
    // Storage for last migration call
    uint256 private _lastTokenId;
    address private _lastL2Owner;
    address private _lastL2Subregistry;
    bytes private _lastData;

    function migrateToNamechain(
        uint256 tokenId,
        address l2Owner,
        address l2Subregistry,
        bytes memory data
    ) external override {
        _lastTokenId = tokenId;
        _lastL2Owner = l2Owner;
        _lastL2Subregistry = l2Subregistry;
        _lastData = data;
    }

    function completeEjection(
        uint256,
        address,
        address,
        uint32,
        uint64,
        bytes memory
    ) external override {}

    function syncRenewalFromL2(
        uint256 tokenId,
        uint64 newExpiry
    ) external override {
        // This would be called by the L2 bridge to update expiry on L1
        L1ETHRegistry(msg.sender).updateExpiration(tokenId, newExpiry);
    }

    // Method to trigger a renewal from L2 for testing
    function triggerSyncRenewalFromL2(
        L1ETHRegistry registry,
        uint256 tokenId,
        uint64 newExpiry
    ) external {
        registry.updateExpiration(tokenId, newExpiry);
    }

    // Method to retrieve the last migration details for assertions
    function getLastMigration()
        external
        view
        returns (uint256, address, address, bytes memory)
    {
        return (_lastTokenId, _lastL2Owner, _lastL2Subregistry, _lastData);
    }
}
