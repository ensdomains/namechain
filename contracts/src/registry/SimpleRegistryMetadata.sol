// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IRegistryMetadata} from "./IRegistryMetadata.sol";
import {EnhancedAccessControl} from "./EnhancedAccessControl.sol";

contract SimpleRegistryMetadata is EnhancedAccessControl, IRegistryMetadata {
    uint256 public constant ROLE_UPDATE_METADATA = 1 << 0;
    uint256 public constant ROLE_UPDATE_METADATA_ADMIN = ROLE_UPDATE_METADATA << 128;

    mapping(uint256 => string) private _tokenUris;

    constructor() {
        _grantRoles(ROOT_RESOURCE, ALL_ROLES, _msgSender());
    }   

    function setTokenUri(uint256 tokenId, string calldata uri) external onlyRoles(ROOT_RESOURCE, ROLE_UPDATE_METADATA) {
        _tokenUris[tokenId] = uri;
    }

    function tokenUri(uint256 tokenId) external view override returns (string memory) {
        return _tokenUris[tokenId];
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IRegistryMetadata).interfaceId || EnhancedAccessControl.supportsInterface(interfaceId);
    }
}