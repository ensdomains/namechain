// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "../../src/common/PermissionedRegistry.sol";

contract MockPermissionedRegistryHelper is PermissionedRegistry {
    constructor(IRegistryDatastore _datastore, IRegistryMetadata _metadata, address _ownerAddress, uint256 _ownerRoles) 
        PermissionedRegistry(_datastore, _metadata, _ownerAddress, _ownerRoles) {}
    
    function testGetResourceFromTokenId(uint256 tokenId) external pure returns (uint256) {
        return getResourceFromTokenId(tokenId);
    }
}