// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC1155Singleton} from "./ERC1155Singleton.sol";
import {IERC1155Singleton} from "./IERC1155Singleton.sol";
import {IRegistry} from "./IRegistry.sol";
import {IRegistryDatastore} from "./IRegistryDatastore.sol";
import {BaseRegistry} from "./BaseRegistry.sol";
import {PermissionedRegistry} from "./PermissionedRegistry.sol";
import {EnhancedAccessControl} from "./EnhancedAccessControl.sol";
import {Roles} from "./Roles.sol";  
import {IRegistryMetadata} from "./IRegistryMetadata.sol";
import {MetadataMixin} from "./MetadataMixin.sol";
import {IETHRegistry} from "./IETHRegistry.sol";
import {NameUtils} from "../utils/NameUtils.sol";


contract ETHRegistry is PermissionedRegistry, MetadataMixin, IETHRegistry {
    error NameAlreadyRegistered(string label);
    error NameExpired(uint256 tokenId);
    error CannotReduceExpiration(uint64 oldExpiration, uint64 newExpiration);

    event NameRenewed(uint256 indexed tokenId, uint64 newExpiration, address renewedBy);
    event NameRelinquished(uint256 indexed tokenId, address relinquishedBy);
    event TokenObserverSet(uint256 indexed tokenId, address observer);

    mapping(uint256 => address) public tokenObservers;
    
    constructor(IRegistryDatastore _datastore, IRegistryMetadata _metadata) PermissionedRegistry(_datastore) MetadataMixin(_metadata) {
        _grantRoles(ROOT_RESOURCE, ROLE_REGISTRAR | ROLE_REGISTRAR_ADMIN | ROLE_RENEW | ROLE_RENEW_ADMIN, _msgSender());
    }

    /**
     * @dev Fetches the token URI for a node.
     * @param tokenId The ID of the node to fetch a URI for.
     * @return The token URI for the node.
     */
    function uri(uint256 tokenId) public view virtual override returns (string memory) {
        return tokenURI(tokenId);
    }

    function ownerOf(uint256 tokenId)
        public
        view
        virtual
        override(ERC1155Singleton, IERC1155Singleton)
        returns (address)
    {
        (, uint96 oldFlags) = datastore.getSubregistry(tokenId);
        uint64 expires = _extractExpiry(oldFlags);
        if (expires < block.timestamp) {
            return address(0);
        }
        return super.ownerOf(tokenId);
    }

    function register(string calldata label, address owner, IRegistry registry, address resolver, uint96 flags, uint256 roleBitmap, uint64 expires)
        public
        onlyRootRoles(ROLE_REGISTRAR)
        returns (uint256 tokenId)
    {
        tokenId = (NameUtils.labelToTokenId(label) & ~uint256(FLAGS_MASK)) | flags;
        flags = (flags & FLAGS_MASK) | (uint96(expires) << 32);

        (, uint96 oldFlags) = datastore.getSubregistry(tokenId);
        uint64 oldExpiry = _extractExpiry(oldFlags);
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

        datastore.setSubregistry(tokenId, address(registry), flags);
        datastore.setResolver(tokenId, resolver, flags);
        emit NewSubname(label);
        return tokenId;
    }

    function setTokenObserver(uint256 tokenId, address _observer) external onlyTokenOwner(tokenId) {
        tokenObservers[tokenId] = _observer;
        emit TokenObserverSet(tokenId, _observer);
    }

    function renew(uint256 tokenId, uint64 expires) public onlyRootRoles(ROLE_RENEW) {
        (address subregistry, uint96 flags) = datastore.getSubregistry(tokenId);
        uint64 oldExpiration = _extractExpiry(flags);
        if (oldExpiration < block.timestamp) {
            revert NameExpired(tokenId);
        }
        if (expires < oldExpiration) {
            revert CannotReduceExpiration(oldExpiration, expires);
        }
        datastore.setSubregistry(tokenId, subregistry, (flags & FLAGS_MASK) | (uint96(expires) << 32));

        address observer = tokenObservers[tokenId];
        if (observer != address(0)) {
            ETHRegistryTokenObserver(observer).onRenew(tokenId, expires, msg.sender);
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
            ETHRegistryTokenObserver(observer).onRelinquish(tokenId, msg.sender);
        }

        emit NameRelinquished(tokenId, msg.sender);
    }

    function nameData(uint256 tokenId) external view returns (uint64 expiry, uint32 flags) {
        (, uint96 _flags) = datastore.getSubregistry(tokenId);
        return (_extractExpiry(_flags), uint32(_flags));
    }

    function setFlags(uint256 tokenId, uint96 flags)
        external
        onlyTokenOwner(tokenId)
        returns (uint256 newTokenId)
    {
        uint96 newFlags = _setFlags(tokenId, flags);
        newTokenId = (tokenId & ~uint256(FLAGS_MASK)) | (newFlags & FLAGS_MASK);
        if (tokenId != newTokenId) {
            address owner = ownerOf(tokenId);
            _mint(owner, newTokenId, 1, "");
            _burn(owner, tokenId, 1);
        }
    }

    function supportsInterface(bytes4 interfaceId) public view override(BaseRegistry, AccessControl, IERC165) returns (bool) {
        return interfaceId == type(IRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    function getSubregistry(string calldata label) external view virtual override(BaseRegistry, IERC165) returns (IRegistry) {
        (address subregistry, uint96 flags) = datastore.getSubregistry(uint256(keccak256(bytes(label))));
        uint64 expires = _extractExpiry(flags);
        if (expires <= block.timestamp) {
            return IRegistry(address(0));
        }
        return IRegistry(subregistry);
    }

    function getResolver(string calldata label) external view virtual override(BaseRegistry, IRegistry) returns (address) {
        uint256 tokenId = uint256(keccak256(bytes(label)));
        (, uint96 flags) = datastore.getSubregistry(tokenId);
        uint64 expires = _extractExpiry(flags);
        if (expires <= block.timestamp) {
            return address(0);
        }

        (address resolver, ) = datastore.getResolver(tokenId);
        return resolver;
    }


    // Internal/private methods

    function _extractExpiry(uint96 flags) private pure returns (uint64) {
        return uint64(flags >> 32);
    }
}

/**
 * @dev Observer pattern for events on existing tokens.
 */
interface ETHRegistryTokenObserver {
    function onRenew(uint256 tokenId, uint64 expires, address renewedBy) external;
    function onRelinquish(uint256 tokenId, address relinquishedBy) external;
}
