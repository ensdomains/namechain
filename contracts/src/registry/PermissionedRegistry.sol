// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {EnhancedAccessControl} from "../access-control/EnhancedAccessControl.sol";
import {IEnhancedAccessControl} from "../access-control/interfaces/IEnhancedAccessControl.sol";
import {EACBaseRolesLib} from "../access-control/libraries/EACBaseRolesLib.sol";
import {ERC1155Singleton} from "../erc1155/ERC1155Singleton.sol";
import {IERC1155Singleton} from "../erc1155/interfaces/IERC1155Singleton.sol";
import {HCAEquivalence} from "../hca/HCAEquivalence.sol";
import {IHCAFactoryBasic} from "../hca/interfaces/IHCAFactoryBasic.sol";
import {LibLabel} from "../utils/LibLabel.sol";

import {BaseRegistry} from "./BaseRegistry.sol";
import {IPermissionedRegistry} from "./interfaces/IPermissionedRegistry.sol";
import {IRegistry} from "./interfaces/IRegistry.sol";
import {IRegistryDatastore} from "./interfaces/IRegistryDatastore.sol";
import {IRegistryMetadata} from "./interfaces/IRegistryMetadata.sol";
import {IStandardRegistry} from "./interfaces/IStandardRegistry.sol";
import {RegistryRolesLib} from "./libraries/RegistryRolesLib.sol";
import {MetadataMixin} from "./MetadataMixin.sol";

contract PermissionedRegistry is
    BaseRegistry,
    EnhancedAccessControl,
    IPermissionedRegistry,
    MetadataMixin
{
    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(
        IRegistryDatastore datastore,
        IHCAFactoryBasic hcaFactory,
        IRegistryMetadata metadata,
        address ownerAddress,
        uint256 ownerRoles
    ) BaseRegistry(datastore) HCAEquivalence(hcaFactory) MetadataMixin(metadata) {
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

    function setSubregistry(uint256 anyId, IRegistry registry) external override {
        (uint256 tokenId, IRegistryDatastore.Entry memory entry) = _checkExpiryAndTokenRoles(
            anyId,
            RegistryRolesLib.ROLE_SET_SUBREGISTRY
        );
        entry.subregistry = registry;
        DATASTORE.setEntry(tokenId, entry);
        emit SubregistryUpdated(tokenId, registry);
    }

    function setResolver(uint256 anyId, address resolver) external override {
        (uint256 tokenId, IRegistryDatastore.Entry memory entry) = _checkExpiryAndTokenRoles(
            anyId,
            RegistryRolesLib.ROLE_SET_RESOLVER
        );
        entry.resolver = resolver;
        DATASTORE.setEntry(tokenId, entry);
        emit ResolverUpdated(tokenId, resolver);
    }

    /// @inheritdoc IStandardRegistry
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

    /// @inheritdoc IStandardRegistry
    function renew(uint256 anyId, uint64 newExpiry) public override {
        (uint256 tokenId, IRegistryDatastore.Entry memory entry) = _checkExpiryAndTokenRoles(
            anyId,
            RegistryRolesLib.ROLE_RENEW
        );
        if (newExpiry < entry.expiry) {
            revert CannotReduceExpiration(entry.expiry, newExpiry);
        }
        entry.expiry = newExpiry;
        DATASTORE.setEntry(tokenId, entry);
        emit ExpiryUpdated(tokenId, newExpiry, _msgSender());
    }

    /// @inheritdoc IEnhancedAccessControl
    function grantRoles(
        uint256 anyId,
        uint256 roleBitmap,
        address account
    ) public override(EnhancedAccessControl, IEnhancedAccessControl) returns (bool) {
        return super.grantRoles(getResource(anyId), roleBitmap, account);
    }

    /// @inheritdoc IEnhancedAccessControl
    function revokeRoles(
        uint256 anyId,
        uint256 roleBitmap,
        address account
    ) public override(EnhancedAccessControl, IEnhancedAccessControl) returns (bool) {
        return super.revokeRoles(getResource(anyId), roleBitmap, account);
    }

    /// @inheritdoc IRegistry
    function getSubregistry(
        string calldata label
    ) public view virtual override(BaseRegistry, IRegistry) returns (IRegistry) {
        IRegistryDatastore.Entry memory entry = getEntry(LibLabel.labelToCanonicalId(label));
        return _isExpired(entry.expiry) ? IRegistry(address(0)) : entry.subregistry;
    }

    /// @inheritdoc IRegistry
    function getResolver(
        string calldata label
    ) public view virtual override(BaseRegistry, IRegistry) returns (address) {
        IRegistryDatastore.Entry memory entry = getEntry(LibLabel.labelToCanonicalId(label));
        return _isExpired(entry.expiry) ? address(0) : entry.resolver;
    }

    /// @inheritdoc ERC1155Singleton
    function uri(uint256 tokenId) public view override returns (string memory) {
        return _tokenURI(tokenId);
    }

    /// @inheritdoc IPermissionedRegistry
    function getEntry(uint256 anyId) public view returns (IRegistryDatastore.Entry memory) {
        return DATASTORE.getEntry(this, anyId);
    }

    /// @inheritdoc IStandardRegistry
    function getExpiry(uint256 anyId) public view returns (uint64) {
        return getEntry(anyId).expiry;
    }

    /// @inheritdoc IPermissionedRegistry
    function getResource(uint256 anyId) public view returns (uint256) {
        return _constructResource(anyId, getEntry(anyId));
    }

    /// @inheritdoc IPermissionedRegistry
    function getTokenId(uint256 anyId) public view returns (uint256) {
        return _constructTokenId(anyId, getEntry(anyId));
    }

    /// @inheritdoc IPermissionedRegistry
    function getNameData(
        string memory label
    ) public view returns (uint256 tokenId, IRegistryDatastore.Entry memory entry) {
        uint256 anyId = LibLabel.labelToCanonicalId(label);
        entry = getEntry(anyId);
        tokenId = _constructTokenId(anyId, entry);
    }

    /// @inheritdoc IPermissionedRegistry
    function latestOwnerOf(uint256 tokenId) public view virtual returns (address) {
        return super.ownerOf(tokenId);
    }

    /// @inheritdoc IERC1155Singleton
    function ownerOf(
        uint256 tokenId
    ) public view virtual override(ERC1155Singleton, IERC1155Singleton) returns (address) {
        IRegistryDatastore.Entry memory entry = getEntry(tokenId);
        return
            tokenId != _constructTokenId(tokenId, entry) || _isExpired(entry.expiry)
                ? address(0)
                : super.ownerOf(tokenId);
    }

    // Enhanced access control methods adapted for token-based resources

    function roles(
        uint256 anyId,
        address account
    ) public view override(EnhancedAccessControl, IEnhancedAccessControl) returns (uint256) {
        return super.roles(getResource(anyId), account);
    }

    function roleCount(
        uint256 anyId
    ) public view override(EnhancedAccessControl, IEnhancedAccessControl) returns (uint256) {
        return super.roleCount(getResource(anyId));
    }

    function hasRoles(
        uint256 anyId,
        uint256 rolesBitmap,
        address account
    ) public view override(EnhancedAccessControl, IEnhancedAccessControl) returns (bool) {
        return super.hasRoles(getResource(anyId), rolesBitmap, account);
    }

    function hasAssignees(
        uint256 anyId,
        uint256 roleBitmap
    ) public view override(EnhancedAccessControl, IEnhancedAccessControl) returns (bool) {
        return super.hasAssignees(getResource(anyId), roleBitmap);
    }

    function getAssigneeCount(
        uint256 anyId,
        uint256 roleBitmap
    )
        public
        view
        override(EnhancedAccessControl, IEnhancedAccessControl)
        returns (uint256 counts, uint256 mask)
    {
        return super.getAssigneeCount(getResource(anyId), roleBitmap);
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
        address prevOwner = super.ownerOf(tokenId);
        if (prevOwner != address(0)) {
            _burn(prevOwner, tokenId, 1);
            ++entry.eacVersionId;
            ++entry.tokenVersionId;
            tokenId = _constructTokenId(tokenId, entry);
        }
        entry.expiry = expires;
        entry.subregistry = registry;
        entry.resolver = resolver;
        DATASTORE.setEntry(tokenId, entry);

        // emit NameRegistered before mint so we can determine this is a registry (in an indexer)
        emit NameRegistered(tokenId, label, expires, _msgSender());

        _mint(owner, tokenId, 1, "");
        _grantRoles(_constructResource(tokenId, entry), roleBitmap, owner, false);

        emit SubregistryUpdated(tokenId, registry);
        emit ResolverUpdated(tokenId, resolver);
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
        bool externalTransfer = to != address(0) && from != address(0);
        if (externalTransfer) {
            // Check ROLE_CAN_TRANSFER for actual transfers only
            // Skip check for mints (from == address(0)) and burns (to == address(0))
            for (uint256 i; i < tokenIds.length; ++i) {
                if (!hasRoles(tokenIds[i], RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN, from)) {
                    revert TransferDisallowed(tokenIds[i], from);
                }
            }
        }
        super._update(from, to, tokenIds, values);
        if (externalTransfer) {
            for (uint256 i; i < tokenIds.length; ++i) {
                _transferRoles(getResource(tokenIds[i]), from, to, false);
            }
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
    function _regenerateToken(uint256 anyId) internal {
        IRegistryDatastore.Entry memory entry = getEntry(anyId);
        if (!_isExpired(entry.expiry)) {
            uint256 tokenId = _constructTokenId(anyId, entry);
            address owner = super.ownerOf(tokenId); // skip expiry check
            if (owner != address(0)) {
                _burn(owner, tokenId, 1);
                ++entry.tokenVersionId;
                DATASTORE.setEntry(tokenId, entry);
                uint256 newTokenId = _constructTokenId(tokenId, entry);
                _mint(owner, newTokenId, 1, "");
                emit TokenRegenerated(tokenId, newTokenId, _constructResource(tokenId, entry));
            }
        }
    }

    /**
     * @dev Override to prevent admin roles from being granted in the registry.
     *
     * In the registry context, admin roles are only assigned during name registration
     * to maintain controlled permission management. This ensures that role delegation
     * follows the intended security model where admin privileges are granted at
     * registration time and cannot be arbitrarily granted afterward.
     *
     * @param resource The resource to get settable roles for.
     * @param account The account to get settable roles for.
     * @return The settable roles (regular roles only, not admin roles).
     */
    function _getSettableRoles(
        uint256 resource,
        address account
    ) internal view virtual override returns (uint256) {
        uint256 allRoles = super.roles(resource, account) | super.roles(ROOT_RESOURCE, account);
        uint256 adminRoleBitmap = allRoles & EACBaseRolesLib.ADMIN_ROLES;
        return adminRoleBitmap >> 128;
    }

    /// @dev Assert token is not expired and caller has necessary roles.
    function _checkExpiryAndTokenRoles(
        uint256 anyId,
        uint256 roleBitmap
    ) internal view returns (uint256 tokenId, IRegistryDatastore.Entry memory entry) {
        entry = getEntry(anyId);
        tokenId = _constructTokenId(anyId, entry);
        if (_isExpired(entry.expiry)) {
            revert NameExpired(tokenId);
        }
        _checkRoles(_constructResource(anyId, entry), roleBitmap, _msgSender());
    }

    /// @dev Internal logic for expired status.
    ///      Only use of `block.timestamp`.
    function _isExpired(uint64 expires) internal view returns (bool) {
        return block.timestamp >= expires;
    }

    /// @dev Create `resource` from parts.
    ///      Returns next resource if token is expired.
    function _constructResource(
        uint256 anyId,
        IRegistryDatastore.Entry memory entry
    ) internal view returns (uint256) {
        return
            LibLabel.getCanonicalId(anyId) |
            (_isExpired(entry.expiry) ? entry.eacVersionId + 1 : entry.eacVersionId);
    }

    /// @dev Create `tokenId` from parts.
    function _constructTokenId(
        uint256 anyId,
        IRegistryDatastore.Entry memory entry
    ) internal pure returns (uint256) {
        return LibLabel.getCanonicalId(anyId) | entry.tokenVersionId;
    }
}
