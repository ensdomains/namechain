// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering, one-contract-per-file

import {
    PermissionedRegistry,
    IRegistryDatastore,
    IRegistryMetadata
} from "~src/common/registry/PermissionedRegistry.sol";

/**
 * @title MockPermissionedRegistry
 * @dev Test contract that extends PermissionedRegistry to expose internal methods
 *      for testing purposes. This allows tests to access getResourceFromTokenId and
 *      getTokenIdFromResource without them being part of the main interface.
 */
contract MockPermissionedRegistry is PermissionedRegistry {
    // Pass through all constructor arguments
    constructor(
        IRegistryDatastore datastore,
        IRegistryMetadata metadata,
        address ownerAddress,
        uint256 ownerRoles
    ) PermissionedRegistry(datastore, metadata, ownerAddress, ownerRoles) {}

    /**
     * @dev Public wrapper for _constructTokenId - for testing only
     */
    function constructTokenId(uint256 id, uint32 tokenVersionId) public pure returns (uint256) {
        IRegistryDatastore.Entry memory entry;
        entry.tokenVersionId = tokenVersionId;
        return _constructTokenId(id, entry);
    }

    /**
     * @dev Test helper that bypasses admin role restrictions - for testing only
     */
    function grantRolesDirect(
        uint256 resource,
        uint256 roleBitmap,
        address account
    ) external returns (bool) {
        return _grantRoles(resource, roleBitmap, account, false);
    }

    /**
     * @dev Test helper that bypasses admin role restrictions - for testing only
     */
    function revokeRolesDirect(
        uint256 resource,
        uint256 roleBitmap,
        address account
    ) external returns (bool) {
        return _revokeRoles(resource, roleBitmap, account, false);
    }
}
