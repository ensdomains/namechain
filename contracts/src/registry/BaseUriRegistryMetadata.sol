// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {EnhancedAccessControl} from "./EnhancedAccessControl.sol";
import {IRegistryMetadata} from "./IRegistryMetadata.sol";
import {Roles} from "./Roles.sol";

contract BaseUriRegistryMetadata is EnhancedAccessControl, IRegistryMetadata, Roles {
    string tokenBaseUri;

    constructor() {
        _grantRoles(ROOT_RESOURCE, ROLE_UPDATE_METADATA, msg.sender);
    }

    function setTokenUri(string calldata uri) external onlyRoles(ROOT_RESOURCE, ROLE_UPDATE_METADATA) {
        tokenBaseUri = uri;
    }

    function tokenUri(uint256 /*tokenId*/) external view returns (string memory) {
        return tokenBaseUri;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IRegistryMetadata).interfaceId || super.supportsInterface(interfaceId);
    }
} 