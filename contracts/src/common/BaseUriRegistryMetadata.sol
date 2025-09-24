// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {
    EnhancedAccessControl,
    LibEACBaseRoles
} from "./EnhancedAccessControl.sol";
import {IRegistryMetadata} from "./IRegistryMetadata.sol";

contract BaseUriRegistryMetadata is EnhancedAccessControl, IRegistryMetadata {
    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    uint256 private constant _ROLE_UPDATE_METADATA = 1 << 0;

    uint256 private constant _ROLE_UPDATE_METADATA_ADMIN =
        _ROLE_UPDATE_METADATA << 128;

    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    string internal _tokenBaseUri;

    ////////////////////////////////////////////////////////////////////////
    // Constructor
    ////////////////////////////////////////////////////////////////////////

    constructor() {
        _grantRoles(
            ROOT_RESOURCE,
            LibEACBaseRoles.ALL_ROLES,
            _msgSender(),
            true
        );
    }

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    function setTokenBaseUri(
        string calldata uri
    ) external onlyRoles(ROOT_RESOURCE, _ROLE_UPDATE_METADATA) {
        _tokenBaseUri = uri;
    }

    function tokenUri(
        uint256 /*tokenId*/
    ) external view returns (string memory) {
        return _tokenBaseUri;
    }

    ////////////////////////////////////////////////////////////////////////
    // Contract support functions
    ////////////////////////////////////////////////////////////////////////

    function supportsInterface(
        bytes4 interfaceId
    ) public view override returns (bool) {
        return
            interfaceId == type(IRegistryMetadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
