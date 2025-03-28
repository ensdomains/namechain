// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IRegistryMetadata} from "./IRegistryMetadata.sol";
import {EnhancedAccessControl} from "./EnhancedAccessControl.sol";

contract BaseUriRegistryMetadata is EnhancedAccessControl, IRegistryMetadata {
    uint256 private constant ROLE_UPDATE_METADATA = 1 << 0;
    uint256 private constant ROLE_UPDATE_METADATA_ADMIN = ROLE_UPDATE_METADATA << 128;

    string tokenBaseUri;

    constructor() {
        _grantRoles(ROOT_RESOURCE, ALL_ROLES, _msgSender());
    }

    function setTokenBaseUri(string calldata uri) external onlyRoles(ROOT_RESOURCE, ROLE_UPDATE_METADATA) {
        tokenBaseUri = uri;
    }

    function tokenUri(uint256 /*tokenId*/) external view returns (string memory) {
        return tokenBaseUri;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IRegistryMetadata).interfaceId || EnhancedAccessControl.supportsInterface(interfaceId);
    }
}