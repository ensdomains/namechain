// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {EnhancedAccessControl} from "../access-control/EnhancedAccessControl.sol";
import {EACBaseRolesLib} from "../access-control/libraries/EACBaseRolesLib.sol";
import {HCAEquivalence} from "../hca/HCAEquivalence.sol";
import {IHCAFactoryBasic} from "../hca/interfaces/IHCAFactoryBasic.sol";

import {IRegistryMetadata} from "./interfaces/IRegistryMetadata.sol";

contract SimpleRegistryMetadata is EnhancedAccessControl, IRegistryMetadata {
    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    uint256 private constant _ROLE_UPDATE_METADATA = 1 << 0;
    uint256 private constant _ROLE_UPDATE_METADATA_ADMIN = _ROLE_UPDATE_METADATA << 128;

    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    mapping(uint256 id => string uri) private _tokenUris;

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(IHCAFactoryBasic hcaFactory) HCAEquivalence(hcaFactory) {
        _grantRoles(ROOT_RESOURCE, EACBaseRolesLib.ALL_ROLES, _msgSender(), true);
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return
            interfaceId == type(IRegistryMetadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    function setTokenUri(
        uint256 tokenId,
        string calldata uri
    ) external onlyRoles(ROOT_RESOURCE, _ROLE_UPDATE_METADATA) {
        _tokenUris[tokenId] = uri;
    }

    function tokenUri(uint256 tokenId) external view override returns (string memory) {
        return _tokenUris[tokenId];
    }
}
