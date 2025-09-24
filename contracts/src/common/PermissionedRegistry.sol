// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {BaseRegistry} from "./BaseRegistry.sol";
import {EnhancedAccessControl} from "./EnhancedAccessControl.sol";
import {ERC1155Singleton} from "./ERC1155Singleton.sol";
import {IEnhancedAccessControl} from "./IEnhancedAccessControl.sol";
import {IERC1155Singleton} from "./IERC1155Singleton.sol";
import {IPermissionedRegistry} from "./IPermissionedRegistry.sol";
import {IRegistry} from "./IRegistry.sol";
import {IRegistryDatastore} from "./IRegistryDatastore.sol";
import {IRegistryMetadata} from "./IRegistryMetadata.sol";
import {ITokenObserver} from "./ITokenObserver.sol";
import {LibRegistryRoles} from "./LibRegistryRoles.sol";
import {MetadataMixin} from "./MetadataMixin.sol";
import {NameUtils} from "./NameUtils.sol";
import {SimpleRegistryMetadata} from "./SimpleRegistryMetadata.sol";

contract PermissionedRegistry is
    BaseRegistry,
    EnhancedAccessControl,
    IPermissionedRegistry,
    MetadataMixin
{
    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    mapping(uint256 tokenId => ITokenObserver tokenObserver) public tokenObservers;

    ////////////////////////////////////////////////////////////////////////
    // Events
    ////////////////////////////////////////////////////////////////////////

    event TokenRegenerated(uint256 oldTokenId, uint256 newTokenId);

    event SubregistryUpdate(uint256 indexed id, address subregistry, uint64 expiry, uint32 data);

    event ResolverUpdate(uint256 indexed id, address resolver, uint32 data);

    ////////////////////////////////////////////////////////////////////////
    // Modifiers
    ////////////////////////////////////////////////////////////////////////

    modifier onlyNonExpiredTokenRoles(uint256 tokenId, uint256 roleBitmap) {
        _checkRoles(_getResourceFromTokenId(tokenId), roleBitmap, _msgSender());
        if (_isExpired(getExpiry(tokenId))) {
            revert NameExpired(tokenId);
        }
        _;
    }

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(
        IRegistryDatastore datastore_,
        IRegistryMetadata metadata_,
        address ownerAddress_,
        uint256 ownerRoles_
    ) BaseRegistry(datastore_) MetadataMixin(metadata_) {
        _grantRoles(ROOT_RESOURCE, ownerRoles_, ownerAddress_, false);

        if (address(metadata_) == address(0)) {
            _updateMetadataProvider(new SimpleRegistryMetadata());
        }
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(BaseRegistry, EnhancedAccessControl, IERC165) returns (bool) {
        return
            interfaceId == type(IPermissionedRegistry).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    /// @notice Burn a name.
    ///         This will destroy the name and remove it from the registry.
    ///
    /// @param tokenId The token ID of the name to relinquish.
    function burn(
        uint256 tokenId
    ) external override onlyNonExpiredTokenRoles(tokenId, LibRegistryRoles.ROLE_BURN) {
        _burn(ownerOf(tokenId), tokenId, 1);

        datastore.setSubregistry(tokenId, address(0), 0, 0);
        emit SubregistryUpdate(tokenId, address(0), 0, 0);

        datastore.setResolver(tokenId, address(0), 0);
        emit ResolverUpdate(tokenId, address(0), 0);

        emit NameBurned(tokenId, msg.sender);
    }

    function setSubregistry(
        uint256 tokenId,
        IRegistry registry
    ) external override onlyNonExpiredTokenRoles(tokenId, LibRegistryRoles.ROLE_SET_SUBREGISTRY) {
        (, uint64 expires, uint32 tokenIdVersion) = datastore.getSubregistry(tokenId);
        datastore.setSubregistry(tokenId, address(registry), expires, tokenIdVersion);
        emit SubregistryUpdate(tokenId, address(registry), expires, tokenIdVersion);
    }

    function setResolver(
        uint256 tokenId,
        address resolver
    ) external override onlyNonExpiredTokenRoles(tokenId, LibRegistryRoles.ROLE_SET_RESOLVER) {
        datastore.setResolver(tokenId, resolver, 0);
        emit ResolverUpdate(tokenId, resolver, 0);
    }

    /// @inheritdoc IPermissionedRegistry
    function latestOwnerOf(uint256 tokenId) external view returns (address) {
        return super.ownerOf(tokenId);
    }

    function getSubregistry(
        string calldata label
    ) external view virtual override(BaseRegistry, IRegistry) returns (IRegistry) {
        uint256 canonicalId = NameUtils.labelToCanonicalId(label);
        (address subregistry, uint64 expires, ) = datastore.getSubregistry(canonicalId);
        return IRegistry(_isExpired(expires) ? address(0) : subregistry);
    }

    function getResolver(
        string calldata label
    ) external view virtual override(BaseRegistry, IRegistry) returns (address) {
        uint256 canonicalId = NameUtils.labelToCanonicalId(label);
        if (_isExpired(getExpiry(canonicalId))) {
            return address(0);
        }
        (address resolver, ) = datastore.getResolver(canonicalId);
        return resolver;
    }

    function register(
        string calldata label,
        address owner,
        IRegistry registry,
        address resolver,
        uint256 roleBitmap,
        uint64 expires
    )
        public
        virtual
        override
        onlyRootRoles(LibRegistryRoles.ROLE_REGISTRAR)
        returns (uint256 tokenId)
    {
        uint64 oldExpiry;
        uint32 tokenIdVersion;
        (tokenId, oldExpiry, tokenIdVersion) = getNameData(label);

        if (!_isExpired(oldExpiry)) {
            revert NameAlreadyRegistered(label);
        }

        if (_isExpired(expires)) {
            revert CannotSetPastExpiration(expires);
        }

        // if there is a previous owner, burn the token
        address previousOwner = super.ownerOf(tokenId);
        if (previousOwner != address(0)) {
            _burn(previousOwner, tokenId, 1);
            tokenIdVersion++; // so we have a fresh acl
        }
        tokenId = _generateTokenId(tokenId, address(registry), expires, tokenIdVersion);

        _mint(owner, tokenId, 1, "");
        _grantRoles(_getResourceFromTokenId(tokenId), roleBitmap, owner, false);

        datastore.setResolver(tokenId, resolver, 0);
        emit ResolverUpdate(tokenId, resolver, 0);

        emit NewSubname(tokenId, label);

        return tokenId;
    }

    function setTokenObserver(
        uint256 tokenId,
        ITokenObserver observer
    ) public override onlyNonExpiredTokenRoles(tokenId, LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER) {
        tokenObservers[tokenId] = observer;
        emit TokenObserverSet(tokenId, address(observer));
    }

    function renew(
        uint256 tokenId,
        uint64 expires
    ) public override onlyNonExpiredTokenRoles(tokenId, LibRegistryRoles.ROLE_RENEW) {
        (address subregistry, uint64 oldExpiration, uint32 tokenIdVersion) = datastore
            .getSubregistry(tokenId);
        if (expires < oldExpiration) {
            revert CannotReduceExpiration(oldExpiration, expires);
        }

        datastore.setSubregistry(tokenId, subregistry, expires, tokenIdVersion);
        emit SubregistryUpdate(tokenId, subregistry, expires, tokenIdVersion);

        ITokenObserver observer = tokenObservers[tokenId];
        if (address(observer) != address(0)) {
            observer.onRenew(tokenId, expires, msg.sender);
        }

        emit NameRenewed(tokenId, expires, msg.sender);
    }

    function grantRoles(
        uint256 tokenId,
        uint256 roleBitmap,
        address account
    ) public override(EnhancedAccessControl, IEnhancedAccessControl) returns (bool) {
        return super.grantRoles(_getResourceFromTokenId(tokenId), roleBitmap, account);
    }

    function revokeRoles(
        uint256 tokenId,
        uint256 roleBitmap,
        address account
    ) public override(EnhancedAccessControl, IEnhancedAccessControl) returns (bool) {
        return super.revokeRoles(_getResourceFromTokenId(tokenId), roleBitmap, account);
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        return _tokenURI(tokenId);
    }

    function getNameData(
        string calldata label
    ) public view returns (uint256 tokenId, uint64 expiry, uint32 tokenIdVersion) {
        uint256 canonicalId = NameUtils.labelToCanonicalId(label);
        (, expiry, tokenIdVersion) = datastore.getSubregistry(canonicalId);
        tokenId = _constructTokenId(canonicalId, tokenIdVersion);
    }

    function getExpiry(uint256 tokenId) public view override returns (uint64) {
        (, uint64 expires, ) = datastore.getSubregistry(tokenId);
        return expires;
    }

    function ownerOf(
        uint256 tokenId
    ) public view virtual override(ERC1155Singleton, IERC1155Singleton) returns (address) {
        return _isExpired(getExpiry(tokenId)) ? address(0) : super.ownerOf(tokenId);
    }

    // Override EnhancedAccessControl methods to use tokenId instead of resource

    function roles(
        uint256 tokenId,
        address account
    ) public view override(EnhancedAccessControl, IEnhancedAccessControl) returns (uint256) {
        return super.roles(_getResourceFromTokenId(tokenId), account);
    }

    function roleCount(
        uint256 tokenId
    ) public view override(EnhancedAccessControl, IEnhancedAccessControl) returns (uint256) {
        return super.roleCount(_getResourceFromTokenId(tokenId));
    }

    function hasRoles(
        uint256 tokenId,
        uint256 rolesBitmap,
        address account
    ) public view override(EnhancedAccessControl, IEnhancedAccessControl) returns (bool) {
        return super.hasRoles(_getResourceFromTokenId(tokenId), rolesBitmap, account);
    }

    function hasAssignees(
        uint256 tokenId,
        uint256 roleBitmap
    ) public view override(EnhancedAccessControl, IEnhancedAccessControl) returns (bool) {
        return super.hasAssignees(_getResourceFromTokenId(tokenId), roleBitmap);
    }

    function getAssigneeCount(
        uint256 tokenId,
        uint256 roleBitmap
    )
        public
        view
        override(EnhancedAccessControl, IEnhancedAccessControl)
        returns (uint256 counts, uint256 mask)
    {
        return super.getAssigneeCount(_getResourceFromTokenId(tokenId), roleBitmap);
    }

    ////////////////////////////////////////////////////////////////////////
    // Internal functions
    ////////////////////////////////////////////////////////////////////////

    /// @dev Override the base registry _update function to transfer the roles to the new owner when the token is transferred.
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal virtual override {
        super._update(from, to, ids, values);

        for (uint256 i = 0; i < ids.length; ++i) {
            /*
            There are two use-cases for this logic:

            1) when transferring a name from one account to another we transfer all roles 
            from the old owner to the new owner.

            2) in _regenerateToken, we burn the token and then mint a new one. This flow below ensures 
            the roles go from owner => zeroAddr => owner during this process.
            */
            _transferRoles(_getResourceFromTokenId(ids[i]), from, to, false);
        }
    }

    /// @dev Override the base registry _onRolesGranted function to regenerate the token when the roles are granted.
    function _onRolesGranted(
        uint256 resource,
        address /*account*/,
        uint256 /*oldRoles*/,
        uint256 /*newRoles*/,
        uint256 /*roleBitmap*/
    ) internal virtual override {
        uint256 tokenId = _getTokenIdFromResource(resource);
        // skip just-burn/expired tokens
        address owner = ownerOf(tokenId);
        if (owner != address(0)) {
            _regenerateToken(tokenId, owner);
        }
    }

    /// @dev Override the base registry _onRolesRevoked function to regenerate the token when the roles are revoked.
    function _onRolesRevoked(
        uint256 resource,
        address /*account*/,
        uint256 /*oldRoles*/,
        uint256 /*newRoles*/,
        uint256 /*roleBitmap*/
    ) internal virtual override {
        uint256 tokenId = _getTokenIdFromResource(resource);
        // skip just-burn/expired tokens
        address owner = ownerOf(tokenId);
        if (owner != address(0)) {
            _regenerateToken(tokenId, owner);
        }
    }

    /// @dev Regenerate a token.
    function _regenerateToken(uint256 tokenId, address owner) internal {
        _burn(owner, tokenId, 1);
        (address registry, uint64 expires, uint32 tokenIdVersion) = datastore.getSubregistry(
            tokenId
        );
        uint256 newTokenId = _generateTokenId(tokenId, registry, expires, tokenIdVersion + 1);
        _mint(owner, newTokenId, 1, "");

        emit TokenRegenerated(tokenId, newTokenId);
    }

    /// @dev Regenerate a token id.
    ///
    /// @param tokenId The token id to regenerate.
    /// @param registry The registry to set.
    /// @param expires The expiry date to set.
    /// @param tokenIdVersion The token id version to set.
    ///
    /// @return newTokenId The new token id.
    function _generateTokenId(
        uint256 tokenId,
        address registry,
        uint64 expires,
        uint32 tokenIdVersion
    ) internal virtual returns (uint256 newTokenId) {
        newTokenId = _constructTokenId(tokenId, tokenIdVersion);
        datastore.setSubregistry(newTokenId, registry, expires, tokenIdVersion);
        emit SubregistryUpdate(newTokenId, registry, expires, tokenIdVersion);
    }

    /// @dev Internal logic for expired status.
    /// @notice Only use of `block.timestamp`.
    function _isExpired(uint64 expires) internal view returns (bool) {
        return block.timestamp >= expires;
    }

    /// @dev Fetches the token ID for a given access control resource ID.
    ///
    /// @param resource The access control resource ID to fetch the token ID for.
    ///
    /// @return The token ID for the resource ID.
    function _getTokenIdFromResource(uint256 resource) internal view returns (uint256) {
        uint256 canonicalId = resource;
        (, , uint32 tokenIdVersion) = datastore.getSubregistry(canonicalId);
        return _constructTokenId(canonicalId, tokenIdVersion);
    }

    /// @dev Fetches the access control resource ID for a given token ID.
    ///
    /// @param tokenId The token ID to fetch the resource ID for.
    ///
    /// @return The access control resource ID for the token ID.
    function _getResourceFromTokenId(uint256 tokenId) internal pure returns (uint256) {
        return NameUtils.getCanonicalId(tokenId);
    }

    /// @dev Construct a token id from a canonical/token id and a token id version.
    ///
    /// @param id The canonical/token id to construct the token id from.
    /// @param tokenIdVersion The token id version to set.
    ///
    /// @return newTokenId The new token id.
    function _constructTokenId(
        uint256 id,
        uint32 tokenIdVersion
    ) internal pure returns (uint256 newTokenId) {
        newTokenId = NameUtils.getCanonicalId(id) | tokenIdVersion;
    }
}
