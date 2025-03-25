// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {RegistryMetadata} from "./RegistryMetadata.sol";

contract BaseUriRegistryMetadata is RegistryMetadata {
    error CannotSetSingleTokenUri();

    string tokenBaseUri;

    constructor() RegistryMetadata(_msgSender()) {
    }

    function setTokenUri(uint256 /*tokenId*/, string calldata /*uri*/) external override {
        revert CannotSetSingleTokenUri();
    }

    function setTokenBaseUri(string calldata uri) external onlyRoles(ROOT_RESOURCE, ROLE_UPDATE_METADATA) {
        tokenBaseUri = uri;
    }

    function tokenUri(uint256 /*tokenId*/) external view override returns (string memory) {
        return tokenBaseUri;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(RegistryMetadata).interfaceId || super.supportsInterface(interfaceId);
    }
}