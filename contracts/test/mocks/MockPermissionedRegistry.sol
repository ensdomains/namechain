// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering, one-contract-per-file

import {IHCAFactoryBasic} from "~src/common/hca/interfaces/IHCAFactoryBasic.sol";
import {
    PermissionedRegistry,
    IRegistryDatastore,
    IRegistryMetadata
} from "~src/common/registry/PermissionedRegistry.sol";
import {LibLabel} from "~src/common/utils/LibLabel.sol";

/**
 * @title MockPermissionedRegistry
 * @dev Test contract that extends PermissionedRegistry to expose internal methods
 *      for testing purposes. This allows tests to access getResourceFromTokenId and
 *      getTokenIdFromResource without them being part of the main interface.
 */
contract MockPermissionedRegistry is PermissionedRegistry {
    // Pass through all constructor arguments
    constructor(
        IRegistryDatastore datastore_,
        IHCAFactoryBasic hcaFactory_,
        IRegistryMetadata metadata_,
        address ownerAddress_,
        uint256 ownerRoles_
    ) PermissionedRegistry(datastore_, hcaFactory_, metadata_, ownerAddress_, ownerRoles_) {}

    /**
     * @dev Public wrapper for getResourceFromTokenId - for testing only
     */
    function testGetResourceFromTokenId(uint256 tokenId) public view returns (uint256) {
        return _getResourceFromTokenId(tokenId);
    }

    /**
     * @dev Public wrapper for getTokenIdFromResource - for testing only
     */
    function testGetTokenIdFromResource(uint256 resource) public view returns (uint256) {
        return _getTokenIdFromResource(resource);
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

    /**
     * @dev Public wrapper for _constructTokenId - for testing only
     */
    function testConstructTokenId(uint256 id, uint32 tokenVersionId) public pure returns (uint256) {
        return _constructTokenId(id, tokenVersionId);
    }

    /**
     * @dev Extract tokenVersionId from a token ID - for testing only
     */
    function testGetTokenVersionId(uint256 tokenId) public pure returns (uint32) {
        // tokenVersionId is in the lower 32 bits
        return uint32(tokenId);
    }

    /**
     * @dev Extract eacVersionId from a resource ID - for testing only
     */
    function testGetEacVersionId(uint256 resourceId) public pure returns (uint32) {
        // eacVersionId is in the lower 32 bits of the resource ID
        return uint32(resourceId & 0xFFFFFFFF);
    }

    /**
     * @dev Helper to get entry data for testing
     */
    function testGetEntry(uint256 tokenId) public view returns (IRegistryDatastore.Entry memory) {
        return DATASTORE.getEntry(address(this), LibLabel.getCanonicalId(tokenId));
    }

    /**
     * @dev Public wrapper for the optimized _getEntry function - for testing only
     */
    function testGetEntryWithCanonicalId(
        uint256 tokenId
    ) public view returns (IRegistryDatastore.Entry memory entry, uint256 canonicalId) {
        return _getEntry(tokenId);
    }

    /**
     * @dev Get eacVersionId from datastore entry for testing
     */
    function testGetEacVersionIdFromEntry(uint256 tokenId) public view returns (uint32) {
        IRegistryDatastore.Entry memory entry = testGetEntry(tokenId);
        return entry.eacVersionId;
    }
}
