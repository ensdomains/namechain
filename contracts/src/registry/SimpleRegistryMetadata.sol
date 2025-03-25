// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {RegistryMetadata} from "./RegistryMetadata.sol";

contract SimpleRegistryMetadata is RegistryMetadata {
    mapping(uint256 => string) private _tokenUris;

    constructor() RegistryMetadata(_msgSender()) {
    }   

    function setTokenUri(uint256 tokenId, string calldata uri) external override onlyRoles(ROOT_RESOURCE, ROLE_UPDATE_METADATA) {
        _tokenUris[tokenId] = uri;
    }

    function tokenUri(uint256 tokenId) external view override returns (string memory) {
        return _tokenUris[tokenId];
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(RegistryMetadata).interfaceId || super.supportsInterface(interfaceId);
    }
} 