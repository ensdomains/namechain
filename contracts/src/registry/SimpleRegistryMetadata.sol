// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IRegistryMetadata} from "./IRegistryMetadata.sol";

contract SimpleRegistryMetadata is AccessControl, IRegistryMetadata {
    bytes32 public constant UPDATE_ROLE = keccak256("UPDATE_ROLE"); 

    mapping(uint256 => string) private _tokenUris;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setTokenUri(uint256 tokenId, string calldata uri) external onlyRole(UPDATE_ROLE) {
        _tokenUris[tokenId] = uri;
    }

    function tokenUri(uint256 tokenId) external view returns (string memory) {
        return _tokenUris[tokenId];
    }
} 