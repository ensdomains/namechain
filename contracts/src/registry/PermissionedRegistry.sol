// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {ERC1155Singleton} from "./ERC1155Singleton.sol";
import {IERC1155Singleton} from "./IERC1155Singleton.sol";
import {IRegistry} from "./IRegistry.sol";
import {IRegistryDatastore} from "./IRegistryDatastore.sol";
import {IRegistryMetadata} from "./IRegistryMetadata.sol";
import {BaseRegistry} from "./BaseRegistry.sol";
import {EnhancedAccessControl} from "./EnhancedAccessControl.sol";
import {Roles} from "./Roles.sol";

abstract contract PermissionedRegistry is BaseRegistry, EnhancedAccessControl, Roles {
    uint96 public constant FLAGS_MASK = 0xffffffff; // 32 bits
    uint96 public constant FLAG_FLAGS_LOCKED = 0x1;

    constructor(IRegistryDatastore _datastore) BaseRegistry(_datastore) EnhancedAccessControl() {
    }

    function _setFlags(uint256 tokenId, uint96 _flags)
        internal
        withSubregistryFlags(tokenId, FLAG_FLAGS_LOCKED, 0)
        returns(uint96 newFlags)
    {
        (address subregistry, uint96 oldFlags) = datastore.getSubregistry(tokenId);
        newFlags = oldFlags | (_flags & FLAGS_MASK);
        if (newFlags != oldFlags) {
            datastore.setSubregistry(tokenId, subregistry, newFlags);
        }
    }

    function setSubregistry(uint256 tokenId, IRegistry registry)
        external
        onlyRoles(tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY)
    {
        (, uint96 _flags) = datastore.getSubregistry(tokenId);
        datastore.setSubregistry(tokenId, address(registry), _flags);
    }

    function setResolver(uint256 tokenId, address resolver)
        external
        onlyRoles(tokenIdResource(tokenId), ROLE_SET_RESOLVER)
    {
        (, uint96 _flags) = datastore.getResolver(tokenId);
        datastore.setResolver(tokenId, resolver, _flags);
    }

    function flags(uint256 tokenId) external view returns(uint96) {
        (, uint96 _flags) = datastore.getSubregistry(tokenId);
        return _flags;
    }

    function supportsInterface(bytes4 interfaceId) public view override(BaseRegistry, EnhancedAccessControl) returns (bool) {
        return BaseRegistry.supportsInterface(interfaceId) || EnhancedAccessControl.supportsInterface(interfaceId);
    }

    function tokenIdResource(uint256 tokenId) public pure returns(bytes32) {
        return bytes32(tokenId & ~uint256(FLAGS_MASK));
    }
    
    // Internal functions

}
