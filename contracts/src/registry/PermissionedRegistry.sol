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
    mapping(uint256 => address) public tokenObservers;

    uint256 public constant ROLE_REGISTRAR = 1 << 0;
    uint256 public constant ROLE_REGISTRAR_ADMIN = ROLE_REGISTRAR << 128;

    uint256 public constant ROLE_RENEW = 1 << 1;
    uint256 public constant ROLE_RENEW_ADMIN = ROLE_RENEW << 128;

    uint256 public constant ROLE_SET_SUBREGISTRY = 1 << 2;
    uint256 public constant ROLE_SET_SUBREGISTRY_ADMIN = ROLE_SET_SUBREGISTRY << 128;

    uint256 public constant ROLE_SET_RESOLVER = 1 << 3;
    uint256 public constant ROLE_SET_RESOLVER_ADMIN = ROLE_SET_RESOLVER << 128;

    uint256 public constant MAX_EXPIRY = type(uint64).max;

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
        (, uint64 expires) = datastore.getSubregistry(tokenId);
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

        (, uint64 oldExpiry) = datastore.getSubregistry(tokenId);
        if (oldExpiry >= block.timestamp) {
            revert NameAlreadyRegistered(label);
        }

        if (expires < block.timestamp) {
            revert CannotSetPastExpiration(expires);
        }

        // if there is a previous owner, burn the token
        address previousOwner = super.ownerOf(tokenId);
        if (previousOwner != address(0)) {
            _burn(previousOwner, tokenId, 1);
        }

        _mint(owner, tokenId, 1, "");
        _grantRoles(tokenIdResource(tokenId), roleBitmap, owner);

        datastore.setSubregistry(tokenId, address(registry), expires);
        datastore.setResolver(tokenId, resolver, 0);

        emit NewSubname(tokenId, label);

        return tokenId;
    }

    function setTokenObserver(uint256 tokenId, address _observer) external onlyTokenOwner(tokenId) {
        tokenObservers[tokenId] = _observer;
        emit TokenObserverSet(tokenId, _observer);
    }

    function renew(uint256 tokenId, uint64 expires) public onlyRootRoles(ROLE_RENEW) {
        (address subregistry, uint64 oldExpiration) = datastore.getSubregistry(tokenId);
        if (oldExpiration < block.timestamp) {
            revert NameExpired(tokenId);
        }
        if (expires < oldExpiration) {
            revert CannotReduceExpiration(oldExpiration, expires);
        }
        datastore.setSubregistry(tokenId, subregistry, expires);

        address observer = tokenObservers[tokenId];
        if (observer != address(0)) {
            PermissionedRegistryTokenObserver(observer).onRenew(tokenId, expires, msg.sender);
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
        _revokeAllRoles(tokenIdResource(tokenId), ownerOf(tokenId));
        _burn(ownerOf(tokenId), tokenId, 1);

        datastore.setSubregistry(tokenId, address(0), 0);
        datastore.setResolver(tokenId, address(0), 0);
        
        address observer = tokenObservers[tokenId];
        if (observer != address(0)) {
            PermissionedRegistryTokenObserver(observer).onRelinquish(tokenId, msg.sender);
        }

        emit NameRelinquished(tokenId, msg.sender);
    }

    function getSubregistry(string calldata label) external view virtual override(BaseRegistry, IRegistry) returns (IRegistry) {
        (address subregistry, uint64 expires) = datastore.getSubregistry(NameUtils.labelToTokenId(label));
        if (expires <= block.timestamp) {
            return IRegistry(address(0));
        }
        return IRegistry(subregistry);
    }

    function getResolver(string calldata label) external view virtual override(BaseRegistry, IRegistry) returns (address) {
        uint256 tokenId = NameUtils.labelToTokenId(label);
        (, uint64 expires) = datastore.getSubregistry(tokenId);
        if (expires <= block.timestamp) {
            return address(0);
        }

        (address resolver, ) = datastore.getResolver(tokenId);
        return resolver;
    }

    function setSubregistry(uint256 tokenId, IRegistry registry)
        external
        onlyRoles(tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY)
    {
        (, uint64 expires) = datastore.getSubregistry(tokenId);
        datastore.setSubregistry(tokenId, address(registry), expires);
    }

    function setResolver(uint256 tokenId, address resolver)
        external
        onlyRoles(tokenIdResource(tokenId), ROLE_SET_RESOLVER)
    {
        datastore.setResolver(tokenId, resolver, 0);
    }

    function nameData(uint256 tokenId) external view returns (uint64 expiry) {
        (, uint64 expires) = datastore.getSubregistry(tokenId);
        return expires;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(BaseRegistry, EnhancedAccessControl, IERC165) returns (bool) {
        return BaseRegistry.supportsInterface(interfaceId) || EnhancedAccessControl.supportsInterface(interfaceId);
    }

    function tokenIdResource(uint256 tokenId) public pure returns(bytes32) {
        return bytes32(tokenId);
    }
}

/**
 * @dev Observer pattern for events on existing tokens.
 */
interface PermissionedRegistryTokenObserver {
    function onRenew(uint256 tokenId, uint64 expires, address renewedBy) external;
    function onRelinquish(uint256 tokenId, address relinquishedBy) external;
}