// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {EnhancedAccessControl} from "./EnhancedAccessControl.sol";

/**
 * @dev Interface for providing metadata URIs for ENSv2 registry contracts.
 */
abstract contract RegistryMetadata is EnhancedAccessControl {
    uint256 public constant ROLE_UPDATE_METADATA = 1 << 0;
    uint256 public constant ROLE_UPDATE_METADATA_ADMIN = ROLE_UPDATE_METADATA << 128;

    constructor(address _admin) {
        _grantRoles(ROOT_RESOURCE, ROLE_UPDATE_METADATA | ROLE_UPDATE_METADATA_ADMIN, _admin);
    }

    /**
     * @dev Sets the token URI for a token ID.
     * @param tokenId The ID of the token to set the URI for.
     * @param uri The URI to set for the token.
     */
    function setTokenUri(uint256 tokenId, string calldata uri) external virtual;

    /**
     * @dev Fetches the token URI for a token ID.
     * @param tokenId The ID of the token to fetch a URI for.
     * @return The token URI for the token.
     */
    function tokenUri(uint256 tokenId) external view virtual returns (string calldata);
}
