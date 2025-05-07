// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";

/**
 * @title MockEjectionController
 * @dev A simple mock controller for testing ejection-related functionality
 */
contract MockEjectionController {
    // Storage for last migration call
    uint256 private _lastTokenId;
    address private _lastL2Owner;
    address private _lastL2Subregistry;
    bytes private _lastData;

    /**
     * @dev Records migration parameters for testing verification
     */
    function migrateToNamechain(
        uint256 tokenId,
        address l2Owner,
        address l2Subregistry,
        bytes memory data
    ) external {
        _lastTokenId = tokenId;
        _lastL2Owner = l2Owner;
        _lastL2Subregistry = l2Subregistry;
        _lastData = data;
    }

    /**
     * @dev Placeholder for ejection completion handling
     */
    function completeEjection(
        uint256,
        address,
        address,
        uint32,
        uint64,
        bytes memory
    ) external {}

    /**
     * @dev Updates expiration on PermissionedRegistry
     */
    function syncRenewalFromL2(
        uint256 tokenId,
        uint64 newExpiry
    ) external {
        // Call renew on PermissionedRegistry
        IPermissionedRegistry(msg.sender).renew(tokenId, newExpiry);
    }

    /**
     * @dev Method to trigger a renewal from L2 for testing
     */
    function triggerSyncRenewalFromL2(
        IPermissionedRegistry registry,
        uint256 tokenId,
        uint64 newExpiry
    ) external {
        registry.renew(tokenId, newExpiry);
    }

    /**
     * @dev Method to retrieve the last migration details for assertions
     */
    function getLastMigration()
        external
        view
        returns (uint256, address, address, bytes memory)
    {
        return (_lastTokenId, _lastL2Owner, _lastL2Subregistry, _lastData);
    }
}
