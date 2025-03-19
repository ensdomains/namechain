// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IRegistryMetadata} from "./IRegistryMetadata.sol";

contract BaseUriRegistryMetadata is AccessControl, IRegistryMetadata {
    bytes32 public constant UPDATE_ROLE = keccak256("UPDATE_ROLE"); 

    string tokenBaseUri;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setTokenUri(string calldata uri) external onlyRole(UPDATE_ROLE) {
        tokenBaseUri = uri;
    }

    function tokenUri(uint256 /*tokenId*/) external view returns (string memory) {
        return tokenBaseUri;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IRegistryMetadata).interfaceId || super.supportsInterface(interfaceId);
    }
} 