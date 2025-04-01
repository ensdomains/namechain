// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC1155Singleton} from "./ERC1155Singleton.sol";
import {IERC1155Singleton} from "./IERC1155Singleton.sol";
import {IRegistry} from "./IRegistry.sol";
import {IRegistryDatastore} from "./IRegistryDatastore.sol";
import {BaseRegistry} from "./BaseRegistry.sol";
import {EnhancedAccessControl} from "./EnhancedAccessControl.sol";
import {MetadataMixin} from "./MetadataMixin.sol";
import {IRegistryMetadata} from "./IRegistryMetadata.sol";
import {SimpleRegistryMetadata} from "./SimpleRegistryMetadata.sol";
import {NameUtils} from "../utils/NameUtils.sol";
import {IPermissionedRegistry} from "./IPermissionedRegistry.sol";

contract PermissionedRegistry is IPermissionedRegistry, BaseRegistry, EnhancedAccessControl, MetadataMixin {
    event TokenIdRegenerated(uint256 oldTokenId, uint256 newTokenId);

    mapping(uint256 => TokenObserver) public tokenObservers;

    mapping(uint256 tokenId => bytes32 resource) public tokenIdResource;
    mapping(bytes32 resource => uint256 tokenId) public resourceTokenId;

    uint256 private constant ROLE_REGISTRAR = 1 << 0;
    uint256 private constant ROLE_REGISTRAR_ADMIN = ROLE_REGISTRAR << 128;

    uint256 private constant ROLE_RENEW = 1 << 1;
    uint256 private constant ROLE_RENEW_ADMIN = ROLE_RENEW << 128;

    uint256 private constant ROLE_SET_SUBREGISTRY = 1 << 2;
    uint256 private constant ROLE_SET_SUBREGISTRY_ADMIN = ROLE_SET_SUBREGISTRY << 128;

    uint256 private constant ROLE_SET_RESOLVER = 1 << 3;
    uint256 private constant ROLE_SET_RESOLVER_ADMIN = ROLE_SET_RESOLVER << 128;

    uint256 private constant ROLE_SET_TOKEN_OBSERVER = 1 << 4;
    uint256 private constant ROLE_SET_TOKEN_OBSERVER_ADMIN = ROLE_SET_TOKEN_OBSERVER << 128;

    uint256 private constant TOKEN_ID_MASK = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000;

    modifier onlyNonExpiredTokenRoles(uint256 tokenId, uint256 roleBitmap) {
        _checkRoles(tokenIdResource[tokenId], roleBitmap, _msgSender());
        (, uint64 expires, ) = _getSubregistryData(tokenId);
        if (expires < block.timestamp) {
            revert NameExpired(tokenId);
        }
        _;
    }

    constructor(IRegistryDatastore _datastore, IRegistryMetadata _metadata) BaseRegistry(_datastore) MetadataMixin(_metadata) {
        _grantRoles(ROOT_RESOURCE, ALL_ROLES, _msgSender());

        if (address(_metadata) == address(0)) {
            _updateMetadataProvider(new SimpleRegistryMetadata());
        }
    }

    function uri(uint256 tokenId ) public view override returns (string memory) {
        return tokenURI(tokenId);
    }

    function ownerOf(uint256 tokenId)
        public
        view
        virtual
        override(ERC1155Singleton, IERC1155Singleton)
        returns (address)
    {
        (, uint64 expires, ) = _getSubregistryData(tokenId);
        if (expires < block.timestamp) {
            return address(0);
        }
        return super.ownerOf(tokenId);
    }

    function register(string calldata label, address owner, IRegistry registry, address resolver, uint256 roleBitmap, uint64 expires)
        public
        onlyRootRoles(ROLE_REGISTRAR)
        returns (uint256 tokenId)
    {
        tokenId = NameUtils.labelToTokenId(label);

        (, uint64 oldExpiry, uint32 tokenIdVersion) = _getSubregistryData(tokenId);
        if (oldExpiry >= block.timestamp) {
            revert NameAlreadyRegistered(label);
        }

        if (expires < block.timestamp) {
            revert CannotSetPastExpiration(expires);
        }

        tokenId = tokenId & TOKEN_ID_MASK | tokenIdVersion;

        // if there is a previous owner, burn the token
        address previousOwner = super.ownerOf(tokenId);
        if (previousOwner != address(0)) {
            _burn(previousOwner, tokenId, 1);
            tokenId = _regenerateTokenId(tokenId);
        }

        _mint(owner, tokenId, 1, "");
        _grantRoles(tokenIdResource[tokenId], roleBitmap, owner);

        datastore.setSubregistry(tokenId, address(registry), expires);
        datastore.setResolver(tokenId, resolver, 0);

        emit NewSubname(tokenId, label);

        return tokenId;
    }

    function setTokenObserver(uint256 tokenId, address _observer) external onlyNonExpiredTokenRoles(tokenId, ROLE_SET_TOKEN_OBSERVER) {
        tokenObservers[tokenId] = TokenObserver(_observer);
        emit TokenObserverSet(tokenId, _observer);
    }

    function renew(uint256 tokenId, uint64 expires) public onlyNonExpiredTokenRoles(tokenId, ROLE_RENEW) {
        (address subregistry, uint64 oldExpiration, ) = _getSubregistryData(tokenId);
        if (expires < oldExpiration) {
            revert CannotReduceExpiration(oldExpiration, expires);
        }
        datastore.setSubregistry(tokenId, subregistry, expires);

        TokenObserver observer = tokenObservers[tokenId];
        if (address(observer) != address(0)) {
            observer.onRenew(tokenId, expires, msg.sender);
        }

        emit NameRenewed(tokenId, expires, msg.sender);
    }

    /**
     * @dev Relinquish a name.
     *      This will destroy the name and remove it from the registry.
     *
     * @param tokenId The token ID of the name to relinquish.
     */
    function relinquish(uint256 tokenId) external onlyTokenOwner(tokenId) {
        _burn(ownerOf(tokenId), tokenId, 1);
        _revokeAllRoles(tokenIdResource[tokenId], ownerOf(tokenId));

        datastore.setSubregistry(tokenId, address(0), 0);
        datastore.setResolver(tokenId, address(0), 0);
        
        TokenObserver observer = tokenObservers[tokenId];
        if (address(observer) != address(0)) {
            observer.onRelinquish(tokenId, msg.sender);
        }

        emit NameRelinquished(tokenId, msg.sender);
    }

    function getSubregistry(string calldata label) external view virtual override(BaseRegistry, IRegistry) returns (IRegistry) {
        uint256 tokenId = NameUtils.labelToTokenId(label);
        (address subregistry, uint64 expires, ) = _getSubregistryData(tokenId);
        if (expires <= block.timestamp) {
            return IRegistry(address(0));
        }
        return IRegistry(subregistry);
    }

    function getResolver(string calldata label) external view virtual override(BaseRegistry, IRegistry) returns (address) {
        uint256 tokenId = NameUtils.labelToTokenId(label);
        (, uint64 expires, ) = _getSubregistryData(tokenId);
        if (expires <= block.timestamp) {
            return address(0);
        }

        (address resolver, ) = datastore.getResolver(tokenId);
        return resolver;
    }

    function setSubregistry(uint256 tokenId, IRegistry registry)
        external
        onlyNonExpiredTokenRoles(tokenId, ROLE_SET_SUBREGISTRY)
    {
        (, uint64 expires, uint32 tokenIdVersion) = _getSubregistryData(tokenId);
        _setSubregistryData(tokenId, address(registry), expires, tokenIdVersion);
    }

    function setResolver(uint256 tokenId, address resolver)
        external
        onlyNonExpiredTokenRoles(tokenId, ROLE_SET_RESOLVER)
    {
        datastore.setResolver(tokenId, resolver, 0);
    }

    function nameData(uint256 tokenId) external view returns (uint64 expiry) {
        (, uint64 expires, ) = _getSubregistryData(tokenId);
        return expires;
    }


    function supportsInterface(bytes4 interfaceId) public view virtual override(BaseRegistry, EnhancedAccessControl, IERC165) returns (bool) {
        return interfaceId == type(IPermissionedRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    function onRolesGranted(bytes32 resource, uint256 roleBitmap, address account) public override {
        tokenIdResource[resourceTokenId[resource]] = resource;
        resourceTokenId[resource] = resourceTokenId[resource];
    }

    function onRolesRevoked(bytes32 resource, uint256 roleBitmap, address account) public override {
        tokenIdResource[resourceTokenId[resource]] = bytes32(0);
        resourceTokenId[resource] = 0;
    }

    // Internal/private methods

    function _mint(address to, uint256 tokenId, uint256 amount, bytes memory data) internal virtual override {
        super._mint(to, tokenId, amount, data);
        tokenIdResource[tokenId] = bytes32(tokenId);
        resourceTokenId[tokenIdResource[tokenId]] = tokenId;
    }

    function _burn(address from, uint256 tokenId, uint256 amount) internal virtual override {
        super._burn(from, tokenId, amount);
        delete tokenIdResource[tokenId];
        delete resourceTokenId[tokenIdResource[tokenId]];
    }

    function _onRolesGranted(bytes32 resource, address account, uint256 oldRoles, uint256 newRoles, uint256 roleBitmap) internal override {
        // if not just minted then regenerate the token id
        if (oldRoles != 0) {
            _regenerateToken(resourceTokenId[resource]);
        }
    }

    function _onRolesRevoked(bytes32 resource, address account, uint256 oldRoles, uint256 newRoles, uint256 roleBitmap) internal override {
        // if not being burnt then regenerate the token id
        if (ownerOf(resourceTokenId[resource]) != address(0)) {
            _regenerateToken(resourceTokenId[resource]);
        }
    }

    function _regenerateToken(uint256 tokenId) internal {
        _burn(ownerOf(tokenId), tokenId, 1);
        uint256 newTokenId = _regenerateTokenId(tokenId);
        _mint(ownerOf(tokenId), newTokenId, 1, "");

        emit TokenIdRegenerated(tokenId, newTokenId);
    }

    function _regenerateTokenId(uint256 tokenId) internal returns (uint256 newTokenId) {
        (address registry, uint64 expires, uint32 tokenIdVersion) = _getSubregistryData(tokenId);
        tokenIdVersion++;
        _setSubregistryData(tokenId, registry, expires, tokenIdVersion);
        newTokenId = _getCanonicalTokenId(tokenId) | tokenIdVersion;
    }

    function _getSubregistryData(uint256 tokenId) internal view returns (address subregistry, uint64 expires, uint32 tokenIdVersion) { 
        uint256 canonicalTokenId = _getCanonicalTokenId(tokenId);
        uint96 data;
        (subregistry, data) = datastore.getSubregistry(canonicalTokenId);
        expires = uint64(data >> 32);
        tokenIdVersion = uint32(data);
    }

    function _setSubregistryData(uint256 tokenId, address subregistry, uint64 expires, uint32 tokenIdVersion) internal { 
        uint256 canonicalTokenId = _getCanonicalTokenId(tokenId);
        datastore.setSubregistry(canonicalTokenId, subregistry, uint96(expires << 32 | tokenIdVersion));
    }

    function _getCanonicalTokenId(uint256 tokenId) internal view returns (uint256) {
        return tokenId & TOKEN_ID_MASK;
    }
}

/**
 * @dev Observer pattern for events on existing tokens.
 */
interface TokenObserver {
    function onRenew(uint256 tokenId, uint64 expires, address renewedBy) external;
    function onRelinquish(uint256 tokenId, address relinquishedBy) external;
}