// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {EnhancedAccessControl} from "./EnhancedAccessControl.sol";
import {IRegistryMetadata} from "./IRegistryMetadata.sol";
import {Roles} from "./Roles.sol";

contract SimpleRegistryMetadata is EnhancedAccessControl, IRegistryMetadata, Roles {
    mapping(uint256 => string) private _tokenUris;

    constructor() EnhancedAccessControl(_msgSender()) {
    }

    function setTokenUri(uint256 tokenId, string calldata uri) external onlyRoles(ROOT_RESOURCE, ROLE_UPDATE_METADATA) {
        _tokenUris[tokenId] = uri;
    }

    function tokenUri(uint256 tokenId) external view returns (string memory) {
        return _tokenUris[tokenId];
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IRegistryMetadata).interfaceId || super.supportsInterface(interfaceId);
    }
} 