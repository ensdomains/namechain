// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {EnhancedAccessControl} from "../access-control/EnhancedAccessControl.sol";
import {IEnhancedAccessControl} from "../access-control/interfaces/IEnhancedAccessControl.sol";
import {ERC1155Singleton} from "../erc1155/ERC1155Singleton.sol";
import {IERC1155Singleton} from "../erc1155/interfaces/IERC1155Singleton.sol";
import {LibLabel} from "../utils/LibLabel.sol";

import {BaseRegistry} from "./BaseRegistry.sol";
import {IPermissionedRegistry} from "./interfaces/IPermissionedRegistry.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";
import {IRegistryDatastore} from "./interfaces/IRegistryDatastore.sol";
import {IRegistryMetadata} from "./interfaces/IRegistryMetadata.sol";
import {ITokenObserver} from "./interfaces/ITokenObserver.sol";
import {RegistryRolesLib} from "./libraries/RegistryRolesLib.sol";
import {MetadataMixin} from "./MetadataMixin.sol";

contract PermissionedRegistry is
    BaseRegistry,
    EnhancedAccessControl,
    IPermissionedRegistry,
    MetadataMixin
{
    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    mapping(uint256 id => ITokenObserver observer) public tokenObservers;

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

    /**
     * @dev Burn a name.
     *      This will destroy the name and remove it from the registry.
     *
     * @param tokenId The token ID of the name to relinquish.
     */
    function burn(
        uint256 tokenId
    ) external override onlyNonExpiredTokenRoles(tokenId, RegistryRolesLib.ROLE_BURN) {
        _burn(ownerOf(tokenId), tokenId, 1);

        (IRegistryDatastore.Entry memory entry, ) = _getEntry(tokenId);
        _setEntry(
            tokenId,
            IRegistryDatastore.Entry({
                subregistry: address(0),
                expiry: 0,
                tokenVersionId: entry.tokenVersionId,
                resolver: address(0),
                eacVersionId: entry.eacVersionId
            })
        );

        // NameBurned implies subregistry/resolver are set to address(0), we don't need to emit those explicitly
        emit NameBurned(tokenId, msg.sender);
    }

    function setSubregistry(
        uint256 tokenId,
        IRegistry registry
    ) external override onlyNonExpiredTokenRoles(tokenId, RegistryRolesLib.ROLE_SET_SUBREGISTRY) {
        DATASTORE.setSubregistry(tokenId, address(registry));
        emit SubregistryUpdate(tokenId, address(registry));
    }

    function setResolver(
        uint256 tokenId,
        address resolver
    ) external override onlyNonExpiredTokenRoles(tokenId, RegistryRolesLib.ROLE_SET_RESOLVER) {
        DATASTORE.setResolver(tokenId, resolver);
        emit ResolverUpdate(tokenId, resolver);
    }

    /// @inheritdoc IPermissionedRegistry
    function latestOwnerOf(uint256 tokenId) external view returns (address) {
        return super.ownerOf(tokenId);
    }

    function getSubregistry(
        string calldata label
    ) external view virtual override(BaseRegistry, IRegistry) returns (IRegistry) {
        uint256 canonicalId = LibLabel.labelToCanonicalId(label);
        IRegistryDatastore.Entry memory entry = DATASTORE.getEntry(address(this), canonicalId);
        return IRegistry(_isExpired(entry.expiry) ? address(0) : entry.subregistry);
    }

    function getResolver(
        string calldata label
    ) external view virtual override(BaseRegistry, IRegistry) returns (address) {
        uint256 canonicalId = LibLabel.labelToCanonicalId(label);
        IRegistryDatastore.Entry memory entry = DATASTORE.getEntry(address(this), canonicalId);
        return _isExpired(entry.expiry) ? address(0) : entry.resolver;
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
        onlyRootRoles(RegistryRolesLib.ROLE_REGISTRAR)
        returns (uint256 tokenId)
    {
        return _register(label, owner, registry, resolver, roleBitmap, expires);
    }

    function setTokenObserver(
        uint256 tokenId,
        ITokenObserver observer
    ) public override onlyNonExpiredTokenRoles(tokenId, RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER) {
        tokenObservers[tokenId] = observer;
        emit TokenObserverSet(tokenId, address(observer));
    }

    function renew(
        uint256 tokenId,
        uint64 expires
    ) public override onlyNonExpiredTokenRoles(tokenId, RegistryRolesLib.ROLE_RENEW) {
        (IRegistryDatastore.Entry memory entry, ) = _getEntry(tokenId);
        if (expires < entry.expiry) {
            revert CannotReduceExpiration(entry.expiry, expires);
        }

        DATASTORE.setExpiry(tokenId, expires);

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
        string memory label
    ) public view returns (uint256 tokenId, IRegistryDatastore.Entry memory entry) {
        uint256 canonicalId = LibLabel.labelToCanonicalId(label);
        entry = DATASTORE.getEntry(address(this), canonicalId);
        tokenId = _constructTokenId(canonicalId, entry.tokenVersionId);
    }

    function getExpiry(uint256 tokenId) public view override returns (uint64) {
        (IRegistryDatastore.Entry memory entry, ) = _getEntry(tokenId);
        return entry.expiry;
    }

    function ownerOf(
        uint256 tokenId
    ) public view virtual override(ERC1155Singleton, IERC1155Singleton) returns (address) {
        return _isExpired(getExpiry(tokenId)) ? address(0) : super.ownerOf(tokenId);
    }

    // Enhanced access control methods adapted for token-based resources

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
    // Internal Functions
    ////////////////////////////////////////////////////////////////////////

    /**
     * @dev Sets an entry in the datastore using a token ID.
     * @param tokenId The token ID to set the entry for.
     * @param entry The entry data to set.
     */
    function _setEntry(uint256 tokenId, IRegistryDatastore.Entry memory entry) internal {
        DATASTORE.setEntry(tokenId, entry);
    }

    /**
     * @dev Internal register method that takes string memory and performs the actual registration logic.
     * @param label The label to register.
     * @param owner The owner of the registered name.
     * @param registry The registry to use for the name.
     * @param resolver The resolver to set for the name.
     * @param roleBitmap The roles to grant to the owner.
     * @param expires The expiration time of the name.
     * @return tokenId The token ID of the registered name.
     */
    function _register(
        string memory label,
        address owner,
        IRegistry registry,
        address resolver,
        uint256 roleBitmap,
        uint64 expires
    ) internal virtual returns (uint256 tokenId) {
        IRegistryDatastore.Entry memory entry;
        (tokenId, entry) = getNameData(label);

        if (!_isExpired(entry.expiry)) {
            revert NameAlreadyRegistered(label);
        }

        if (_isExpired(expires)) {
            revert CannotSetPastExpiration(expires);
        }

        // if there is a previous owner, burn the token and increment the acl version id
        if (entry.expiry > 0) {
            address previousOwner = super.ownerOf(tokenId);
            if (previousOwner != address(0)) {
                _burn(previousOwner, tokenId, 1);
            }
            entry.eacVersionId++;
            entry.tokenVersionId++;
        }

        uint256 canonicalId = LibLabel.getCanonicalId(tokenId);
        tokenId = _generateTokenId(
            canonicalId,
            IRegistryDatastore.Entry({
                subregistry: address(registry),
                expiry: expires,
                tokenVersionId: entry.tokenVersionId,
                resolver: resolver,
                eacVersionId: entry.eacVersionId
            })
        );

        // emit nameregistered before mint so we can determine this is a registry (in an indexer)
        emit NameRegistered(tokenId, label, expires, msg.sender);

        _mint(owner, tokenId, 1, "");
        _grantRoles(_getResourceFromTokenId(tokenId), roleBitmap, owner, false);

        emit SubregistryUpdate(tokenId, address(registry));
        emit ResolverUpdate(tokenId, resolver);

        return tokenId;
    }

    /**
     * @dev Override the base registry _update function to transfer the roles to the new owner when the token is transferred.
     */
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal virtual override {
        // Check ROLE_CAN_TRANSFER for actual transfers only
        // Skip check for mints (from == address(0)) and burns (to == address(0))
        if (from != address(0) && to != address(0)) {
            for (uint256 i = 0; i < ids.length; ++i) {
                uint256 resource = _getResourceFromTokenId(ids[i]);
                if (!hasRoles(resource, RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN, from)) {
                    revert TransferDisallowed(ids[i], from);
                }
            }
        }

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

    /**
     * @dev Override the base registry _onRolesGranted function to regenerate the token when the roles are granted.
     */
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

    /**
     * @dev Override the base registry _onRolesRevoked function to regenerate the token when the roles are revoked.
     */
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

    /**
     * @dev Regenerate a token.
     */
    function _regenerateToken(uint256 tokenId, address owner) internal {
        _burn(owner, tokenId, 1);
        (IRegistryDatastore.Entry memory entry, uint256 canonicalId) = _getEntry(tokenId);
        entry.tokenVersionId = entry.tokenVersionId + 1;
        uint256 newTokenId = _generateTokenId(canonicalId, entry);
        _mint(owner, newTokenId, 1, "");

        emit TokenRegenerated(tokenId, newTokenId);
    }

    /**
     * @dev Regenerate a token id.
     * @param canonicalId The canonical id to regenerate.
     * @param entry The entry data to set (and also contains information used to generate the token id).
     * @return newTokenId The new token id.
     */
    function _generateTokenId(
        uint256 canonicalId,
        IRegistryDatastore.Entry memory entry
    ) internal virtual returns (uint256 newTokenId) {
        newTokenId = _constructTokenId(canonicalId, entry.tokenVersionId);
        DATASTORE.setEntry(canonicalId, entry);
    }

    /**
     * @dev Fetches an entry from the datastore using a token ID.
     * @param tokenId The token ID to fetch the entry for.
     * @return entry The datastore entry for the token ID.
     * @return canonicalId The canonical ID for the token ID.
     */
    function _getEntry(
        uint256 tokenId
    ) internal view returns (IRegistryDatastore.Entry memory entry, uint256 canonicalId) {
        canonicalId = LibLabel.getCanonicalId(tokenId);
        entry = DATASTORE.getEntry(address(this), canonicalId);
    }

    /// @dev Internal logic for expired status.
    /// @notice Only use of `block.timestamp`.
    function _isExpired(uint64 expires) internal view returns (bool) {
        return block.timestamp >= expires;
    }

    /**
     * @dev Fetches the access control resource ID for a given token ID.
     * @param tokenId The token ID to fetch the resource ID for.
     * @return The access control resource ID for the token ID.
     */
    function _getResourceFromTokenId(uint256 tokenId) internal view returns (uint256) {
        (IRegistryDatastore.Entry memory entry, uint256 canonicalId) = _getEntry(tokenId);
        return canonicalId | uint256(entry.eacVersionId);
    }

    /**
     * @dev Fetches the token ID for a given access control resource ID.
     * @param resource The access control resource ID to fetch the token ID for.
     * @return The token ID for the resource ID.
     */
    function _getTokenIdFromResource(uint256 resource) internal view returns (uint256) {
        (IRegistryDatastore.Entry memory entry, uint256 canonicalId) = _getEntry(resource);
        return _constructTokenId(canonicalId, entry.tokenVersionId);
    }

    /**
     * @dev Construct a token id from a canonical/token id and a token version.
     * @param canonicalId The canonical id to construct the token id from.
     * @param tokenVersionId The token version ID to set.
     * @return newTokenId The new token id.
     */
    function _constructTokenId(
        uint256 canonicalId,
        uint32 tokenVersionId
    ) internal pure returns (uint256 newTokenId) {
        newTokenId = canonicalId | uint256(tokenVersionId);
    }
}
