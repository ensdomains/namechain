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
import {IStandardRegistry} from "./interfaces/IStandardRegistry.sol";
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

    mapping(uint256 tokenId => ITokenObserver observer) public tokenObservers;

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(
        IRegistryDatastore datastore,
        IRegistryMetadata metadata,
        address ownerAddress,
        uint256 ownerRoles
    ) BaseRegistry(datastore) MetadataMixin(metadata) {
        _grantRoles(ROOT_RESOURCE, ownerRoles, ownerAddress, false);
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

    /// @inheritdoc IStandardRegistry
    function burn(uint256 id) external override {
        (uint256 tokenId, IRegistryDatastore.Entry memory entry) = _checkTokenRolesAndExpiry(
            id,
            RegistryRolesLib.ROLE_BURN
        );
        _burn(super.ownerOf(tokenId), tokenId, 1); // skip expiry check
        entry.expiry = 0;
        entry.resolver = address(0);
        entry.subregistry = address(0);
        DATASTORE.setEntry(id, entry);
        // NameBurned implies subregistry/resolver are set to address(0), we don't need to emit those explicitly
        emit NameBurned(tokenId, msg.sender);
    }

    function setSubregistry(uint256 id, IRegistry registry) external override {
        (uint256 tokenId, IRegistryDatastore.Entry memory entry) = _checkTokenRolesAndExpiry(
            id,
            RegistryRolesLib.ROLE_SET_SUBREGISTRY
        );
        entry.subregistry = address(registry);
        DATASTORE.setEntry(tokenId, entry);
        emit SubregistryUpdate(tokenId, address(registry));
    }

    function setResolver(uint256 id, address resolver) external override {
        (uint256 tokenId, IRegistryDatastore.Entry memory entry) = _checkTokenRolesAndExpiry(
            id,
            RegistryRolesLib.ROLE_SET_RESOLVER
        );
        entry.resolver = resolver;
        DATASTORE.setEntry(tokenId, entry);
        emit ResolverUpdate(tokenId, resolver);
    }

    function getSubregistry(
        string calldata label
    ) external view virtual override(BaseRegistry, IRegistry) returns (IRegistry) {
        IRegistryDatastore.Entry memory entry = getEntry(LibLabel.labelToCanonicalId(label));
        return IRegistry(_isExpired(entry.expiry) ? address(0) : entry.subregistry);
    }

    function getResolver(
        string calldata label
    ) external view virtual override(BaseRegistry, IRegistry) returns (address) {
        IRegistryDatastore.Entry memory entry = getEntry(LibLabel.labelToCanonicalId(label));
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

    function setTokenObserver(uint256 id, ITokenObserver observer) public override {
        (uint256 tokenId, ) = _checkTokenRolesAndExpiry(
            id,
            RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER
        );
        tokenObservers[tokenId] = observer;
        emit TokenObserverSet(tokenId, address(observer));
    }

    function renew(uint256 id, uint64 expires) public override {
        (uint256 tokenId, IRegistryDatastore.Entry memory entry) = _checkTokenRolesAndExpiry(
            id,
            RegistryRolesLib.ROLE_RENEW
        );
        if (expires < entry.expiry) {
            revert CannotReduceExpiration(entry.expiry, expires);
        }
        entry.expiry = expires;
        DATASTORE.setEntry(tokenId, entry);
        ITokenObserver observer = tokenObservers[tokenId];
        if (address(observer) != address(0)) {
            observer.onRenew(tokenId, expires, msg.sender);
        }
        emit NameRenewed(tokenId, expires, msg.sender);
    }

    function grantRoles(
        uint256 id,
        uint256 roleBitmap,
        address account
    ) public override(EnhancedAccessControl, IEnhancedAccessControl) returns (bool) {
        return super.grantRoles(getResource(id), roleBitmap, account);
    }

    function revokeRoles(
        uint256 id,
        uint256 roleBitmap,
        address account
    ) public override(EnhancedAccessControl, IEnhancedAccessControl) returns (bool) {
        return super.revokeRoles(getResource(id), roleBitmap, account);
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        return _tokenURI(tokenId);
    }

    /// @dev Shorthand to get datastore entry.
    function getEntry(uint256 id) public view returns (IRegistryDatastore.Entry memory) {
        return DATASTORE.getEntry(address(this), id);
    }

    /// @dev Shorthand to get datastore expiry.
    function getExpiry(uint256 tokenId) public view override returns (uint64) {
        return getEntry(tokenId).expiry;
    }

    /// @dev Shorthand to get resource from token.
    function getResource(uint256 id) public view returns (uint256) {
        return _constructResource(id, getEntry(id));
    }

    function getNameData(
        string memory label
    ) public view returns (uint256 tokenId, IRegistryDatastore.Entry memory entry) {
        uint256 id = LibLabel.labelToCanonicalId(label);
        entry = getEntry(id);
        tokenId = _constructTokenId(id, entry);
    }

    /// @inheritdoc IPermissionedRegistry
    function latestOwnerOf(uint256 tokenId) public view virtual returns (address) {
        return super.ownerOf(tokenId);
    }

    /// @inheritdoc IERC1155Singleton
    function ownerOf(
        uint256 id
    ) public view virtual override(ERC1155Singleton, IERC1155Singleton) returns (address) {
        IRegistryDatastore.Entry memory entry = getEntry(id);
        uint256 tokenId = _constructTokenId(id, entry);
        return tokenId != id || _isExpired(entry.expiry) ? address(0) : super.ownerOf(tokenId);
    }

    // Enhanced access control methods adapted for token-based resources

    function roles(
        uint256 id,
        address account
    ) public view override(EnhancedAccessControl, IEnhancedAccessControl) returns (uint256) {
        return super.roles(getResource(id), account);
    }

    function roleCount(
        uint256 id
    ) public view override(EnhancedAccessControl, IEnhancedAccessControl) returns (uint256) {
        return super.roleCount(getResource(id));
    }

    function hasRoles(
        uint256 id,
        uint256 rolesBitmap,
        address account
    ) public view override(EnhancedAccessControl, IEnhancedAccessControl) returns (bool) {
        return super.hasRoles(getResource(id), rolesBitmap, account);
    }

    function hasAssignees(
        uint256 id,
        uint256 roleBitmap
    ) public view override(EnhancedAccessControl, IEnhancedAccessControl) returns (bool) {
        return super.hasAssignees(getResource(id), roleBitmap);
    }

    function getAssigneeCount(
        uint256 id,
        uint256 roleBitmap
    )
        public
        view
        override(EnhancedAccessControl, IEnhancedAccessControl)
        returns (uint256 counts, uint256 mask)
    {
        return super.getAssigneeCount(getResource(id), roleBitmap);
    }

    ////////////////////////////////////////////////////////////////////////
    // Internal Functions
    ////////////////////////////////////////////////////////////////////////

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
        tokenId = LibLabel.labelToCanonicalId(label);
        IRegistryDatastore.Entry memory entry = getEntry(tokenId);
        if (!_isExpired(entry.expiry)) {
            revert NameAlreadyRegistered(label);
        }
        if (_isExpired(expires)) {
            revert CannotSetPastExpiration(expires);
        }
        tokenId = _constructTokenId(tokenId, entry);
        if (entry.expiry > 0) {
            _burn(super.ownerOf(tokenId), tokenId, 1); // nonzero by construction
            ++entry.eacVersionId;
            ++entry.tokenVersionId;
            tokenId = _constructTokenId(tokenId, entry);
        }
        entry.expiry = expires;
        entry.subregistry = address(registry);
        entry.resolver = resolver;
        DATASTORE.setEntry(tokenId, entry);

        // emit NameRegistered before mint so we can determine this is a registry (in an indexer)
        emit NameRegistered(tokenId, label, expires, msg.sender);

        _mint(owner, tokenId, 1, "");
        _grantRoles(_constructResource(tokenId, entry), roleBitmap, owner, false);

        emit SubregistryUpdate(tokenId, address(registry));
        emit ResolverUpdate(tokenId, resolver);
    }

    /**
     * @dev Override the base registry _update function to transfer the roles to the new owner when the token is transferred.
     */
    function _update(
        address from,
        address to,
        uint256[] memory tokenIds,
        uint256[] memory values
    ) internal virtual override {
        // Check ROLE_CAN_TRANSFER for actual transfers only
        // Skip check for mints (from == address(0)) and burns (to == address(0))
        if (from != address(0) && to != address(0)) {
            for (uint256 i = 0; i < tokenIds.length; ++i) {
                if (!hasRoles(tokenIds[i], RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN, from)) {
                    revert TransferDisallowed(tokenIds[i], from);
                }
            }
        }

        super._update(from, to, tokenIds, values);

        for (uint256 i = 0; i < tokenIds.length; ++i) {
            /*
            There are two use-cases for this logic:

            1) when transferring a name from one account to another we transfer all roles 
            from the old owner to the new owner.

            2) in _regenerateToken, we burn the token and then mint a new one. This flow below ensures 
            the roles go from owner => zeroAddr => owner during this process.
            */
            _transferRoles(getResource(tokenIds[i]), from, to, false);
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
        _regenerateToken(resource);
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
        _regenerateToken(resource);
    }

    /// @dev Bump `tokenVersionId` via burn+mint if token is not expired.
    function _regenerateToken(uint256 id) internal {
        IRegistryDatastore.Entry memory entry = getEntry(id);
        if (!_isExpired(entry.expiry)) {
            uint256 tokenId = _constructTokenId(id, entry);
            address owner = super.ownerOf(tokenId); // skip expiry check
            if (owner != address(0)) {
                _burn(owner, tokenId, 1);
                ++entry.tokenVersionId;
                DATASTORE.setEntry(tokenId, entry);
                uint256 newTokenId = _constructTokenId(tokenId, entry);
                _mint(owner, newTokenId, 1, "");
                emit TokenRegenerated(tokenId, newTokenId);
            }
        }
    }

    /// @dev Assert caller has necessary roles and token is not expired.
    function _checkTokenRolesAndExpiry(
        uint256 id,
        uint256 roleBitmap
    ) internal view returns (uint256 tokenId, IRegistryDatastore.Entry memory entry) {
        entry = getEntry(id);
        _checkRoles(_constructResource(id, entry), roleBitmap, _msgSender());
        tokenId = _constructTokenId(id, entry);
        if (_isExpired(entry.expiry)) {
            revert NameExpired(tokenId);
        }
    }

    /// @dev Internal logic for expired status.
    ///      Only use of `block.timestamp`.
    function _isExpired(uint64 expires) internal view returns (bool) {
        return block.timestamp >= expires;
    }

    /// @dev Create `tokenId` from parts.
    function _constructTokenId(
        uint256 id,
        IRegistryDatastore.Entry memory entry
    ) internal pure returns (uint256) {
        return LibLabel.getCanonicalId(id) | entry.tokenVersionId;
    }

    /// @dev Create `resource` from parts.
    function _constructResource(
        uint256 id,
        IRegistryDatastore.Entry memory entry
    ) internal pure returns (uint256) {
        return LibLabel.getCanonicalId(id) | entry.eacVersionId;
    }
}
