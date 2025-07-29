// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "../../src/common/PermissionedRegistry.sol";

/**
 * @title MockPermissionedRegistry
 * @dev Test mock that exposes internal methods of PermissionedRegistry as public
 *      for testing purposes. This allows tests to access getTokenIdResource and 
 *      getResourceTokenId without them being part of the main interface.
 */
contract MockPermissionedRegistry is PermissionedRegistry {
    constructor(
        IRegistryDatastore _datastore,
        IRegistryMetadata _metadata,
        address _ownerAddress,
        uint256 _ownerRoles
    ) PermissionedRegistry(_datastore, _metadata, _ownerAddress, _ownerRoles) {}

    /**
     * @dev Public wrapper for getTokenIdResource - for testing only
     */
    function testGetTokenIdResource(uint256 tokenId) public pure returns (uint256) {
        return getTokenIdResource(tokenId);
    }

    /**
     * @dev Public wrapper for getResourceTokenId - for testing only
     */
    function testGetResourceTokenId(uint256 resource) public view returns (uint256) {
        return getResourceTokenId(resource);
    }
} 