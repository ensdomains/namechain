// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "../../src/common/PermissionedRegistry.sol";

/**
 * @title MockPermissionedRegistry
 * @dev Test contract that extends PermissionedRegistry to expose internal methods
 *      for testing purposes. This allows tests to access getResourceFromTokenId and
 *      getTokenIdFromResource without them being part of the main interface.
 */
contract MockPermissionedRegistry is PermissionedRegistry {

    // Pass through all constructor arguments
    constructor(IRegistryDatastore _datastore, IRegistryMetadata _metadata, address _ownerAddress, uint256 _ownerRoles) 
        PermissionedRegistry(_datastore, _metadata, _ownerAddress, _ownerRoles) {}

    /**
     * @dev Public wrapper for getResourceFromTokenId - for testing only
     */
    function testGetResourceFromTokenId(uint256 tokenId) public pure returns (uint256) {
        return getResourceFromTokenId(tokenId);
    }

    /**
     * @dev Public wrapper for getTokenIdFromResource - for testing only
     */
    function testGetTokenIdFromResource(uint256 resource) public view returns (uint256) {
        return getTokenIdFromResource(resource);
    }

    /**
     * @dev Test helper that bypasses admin role restrictions - for testing only
     */
    function grantRolesDirect(uint256 resource, uint256 roleBitmap, address account) external returns (bool) {
        return _grantRoles(resource, roleBitmap, account, false);
    }
    
    /**
     * @dev Test helper that bypasses admin role restrictions - for testing only
     */
    function revokeRolesDirect(uint256 resource, uint256 roleBitmap, address account) external returns (bool) {
        return _revokeRoles(resource, roleBitmap, account, false);
    }
} 