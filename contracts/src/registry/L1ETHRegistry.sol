// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {ERC1155Singleton} from "./ERC1155Singleton.sol";
import {IERC1155Singleton} from "./IERC1155Singleton.sol";
import {IRegistry} from "./IRegistry.sol";
import {IRegistryDatastore} from "./IRegistryDatastore.sol";
import {BaseRegistry} from "./BaseRegistry.sol";
import {PermissionedRegistry} from "./PermissionedRegistry.sol";

/**
 * @title L1ETHRegistry
 * @dev L1 contract for .eth that holds ejected .eth names only.
 * Unlike the L2 ETHRegistry, this registry does not handle new registrations directly,
 * but receives names that have been ejected from L2.
 */
contract L1ETHRegistry is PermissionedRegistry, AccessControl {
    bytes32 public constant EJECTION_CONTROLLER_ROLE = keccak256("EJECTION_CONTROLLER_ROLE");
    bytes32 public constant RENEWAL_CONTROLLER_ROLE = keccak256("RENEWAL_CONTROLLER_ROLE");

    error NameNotEjected(string label);
    error NameExpired(uint256 tokenId);
    error CannotReduceExpiration(uint64 oldExpiration, uint64 newExpiration);

    event NameEjected(uint256 indexed tokenId, address owner, uint64 expires);
    event NameRenewed(uint256 indexed tokenId, uint64 newExpiration, address renewedBy);
    event NameRelinquished(uint256 indexed tokenId, address relinquishedBy);
    event NameMigratedToL2(uint256 indexed tokenId, address sendTo);
    event FallbackResolverSet(address resolver);
    event TokenObserverSet(uint256 indexed tokenId, address observer);

    // Address of the fallback resolver for names not found in this registry
    address public fallbackResolver;

    // Map to track token observers for notification of renewal/ejection events
    mapping(uint256 => address) public tokenObservers;

    constructor(IRegistryDatastore _datastore) PermissionedRegistry(_datastore) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function uri(uint256 /*tokenId*/ ) public pure override returns (string memory) {
        return "";
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

    /**
     * @dev Receive an ejected name from L2.
     * @param label The label of the name
     * @param owner The owner of the name
     * @param registry The registry to use for the name
     * @param flags Additional flags for the name
     * @param expires Expiration timestamp
     * @return tokenId The token ID of the ejected name
     */
    function ejectFromL2(string calldata label, address owner, IRegistry registry, uint96 flags, uint64 expires)
        public
        onlyRole(EJECTION_CONTROLLER_ROLE)
        returns (uint256 tokenId)
    {
        tokenId = (uint256(keccak256(bytes(label))) & ~uint256(FLAGS_MASK)) | flags;
        flags = (flags & FLAGS_MASK) | (uint96(expires) << 32);

        // If there is a previous owner, burn the token
        address previousOwner = super.ownerOf(tokenId);
        if (previousOwner != address(0)) {
            _burn(previousOwner, tokenId, 1);
        }

        _mint(owner, tokenId, 1, "");
        datastore.setSubregistry(tokenId, address(registry), flags);
        emit NewSubname(label);
        emit NameEjected(tokenId, owner, expires);
        return tokenId;
    }

    /**
     * @dev Renew an ejected name
     * @param tokenId The token ID of the name to renew
     * @param expires New expiration timestamp
     */
    function renew(uint256 tokenId, uint64 expires) public onlyRole(RENEWAL_CONTROLLER_ROLE) {
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
            L1ETHRegistryTokenObserver(observer).onRenew(tokenId, expires, msg.sender);
        }

        emit NameRenewed(tokenId, expires, msg.sender);
    }

    /**
     * @dev Set the token observer for a name
     * @param tokenId The token ID of the name
     * @param _observer The observer address
     */
    function setTokenObserver(uint256 tokenId, address _observer) external onlyTokenOwner(tokenId) {
        tokenObservers[tokenId] = _observer;
        emit TokenObserverSet(tokenId, _observer);
    }

    /**
     * @dev Relinquish an ejected name
     * @param tokenId The token ID of the name to relinquish
     */
    function relinquish(uint256 tokenId) external onlyTokenOwner(tokenId) {
        _burn(ownerOf(tokenId), tokenId, 1);
        datastore.setSubregistry(tokenId, address(0), 0);

        address observer = tokenObservers[tokenId];
        if (observer != address(0)) {
            L1ETHRegistryTokenObserver(observer).onRelinquish(tokenId, msg.sender);
        }

        emit NameRelinquished(tokenId, msg.sender);
    }

    /**
     * @dev Migrate a name back to L2
     * @param tokenId The token ID of the name to migrate
     * @param sendTo The address to send the name to on L2
     */
    function migrateToL2(uint256 tokenId, address sendTo)
        external
        onlyTokenOwner(tokenId)
        onlyRole(EJECTION_CONTROLLER_ROLE)
    {
        address owner = ownerOf(tokenId);
        _burn(owner, tokenId, 1);
        datastore.setSubregistry(tokenId, address(0), 0);

        emit NameMigratedToL2(tokenId, sendTo);
    }

    /**
     * @dev Set the fallback resolver for names not found in this registry
     * @param _fallbackResolver The address of the fallback resolver
     */
    function setFallbackResolver(address _fallbackResolver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        fallbackResolver = _fallbackResolver;
        emit FallbackResolverSet(_fallbackResolver);
    }

    /**
     * @dev Get name data (expiry and flags)
     * @param tokenId The token ID of the name
     * @return expiry Expiration timestamp
     * @return flags Flags for the name
     */
    function nameData(uint256 tokenId) external view returns (uint64 expiry, uint32 flags) {
        (, uint96 _flags) = datastore.getSubregistry(tokenId);
        return (_extractExpiry(_flags), uint32(_flags));
    }

    /**
     * @dev Set flags for a name
     * @param tokenId The token ID of the name
     * @param flags The new flags
     * @return newTokenId The new token ID (may change if flags affect the ID)
     */
    function setFlags(uint256 tokenId, uint96 flags) external onlyTokenOwner(tokenId) returns (uint256 newTokenId) {
        uint96 newFlags = _setFlags(tokenId, flags);
        newTokenId = (tokenId & ~uint256(FLAGS_MASK)) | (newFlags & FLAGS_MASK);
        if (tokenId != newTokenId) {
            address owner = ownerOf(tokenId);
            _burn(owner, tokenId, 1);
            _mint(owner, newTokenId, 1, "");
        }
    }

    function supportsInterface(bytes4 interfaceId) public view override(BaseRegistry, AccessControl) returns (bool) {
        return interfaceId == type(IRegistry).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Get the subregistry for a label
     * @param label The label to query
     * @return The registry for the label, or address(0) if not found or expired
     */
    function getSubregistry(string calldata label) external view virtual override returns (IRegistry) {
        (address subregistry, uint96 flags) = datastore.getSubregistry(uint256(keccak256(bytes(label))));
        uint64 expires = _extractExpiry(flags);
        if (expires <= block.timestamp) {
            return IRegistry(address(0));
        }
        return IRegistry(subregistry);
    }

    /**
     * @dev Get the resolver for a label
     * @param label The label to query
     * @return The resolver for the label, or the fallback resolver if not found or expired
     */
    function getResolver(string calldata label) external view virtual override returns (address) {
        uint256 tokenId = uint256(keccak256(bytes(label)));
        (, uint96 flags) = datastore.getSubregistry(tokenId);
        uint64 expires = _extractExpiry(flags);

        if (expires <= block.timestamp) {
            return fallbackResolver;
        }

        (address resolver,) = datastore.getResolver(tokenId);
        return resolver != address(0) ? resolver : fallbackResolver;
    }

    // Private methods

    function _extractExpiry(uint96 flags) private pure returns (uint64) {
        return uint64(flags >> 32);
    }
}

/**
 * @dev Observer pattern for events on existing tokens.
 */
interface L1ETHRegistryTokenObserver {
    function onRenew(uint256 tokenId, uint64 expires, address renewedBy) external;
    function onRelinquish(uint256 tokenId, address relinquishedBy) external;
}
