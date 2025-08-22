// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IRegistry} from "./IRegistry.sol";

/**
 * @title IStandardRegistry
 * @dev Interface for the a standard registry.
 */
interface IStandardRegistry is IRegistry {
    /**
     * @dev Error emitted when a name is already registered.
     */
    error NameAlreadyRegistered(string label);

    /**
     * @dev Error emitted when a name has expired.
     */
    error NameExpired(uint256 tokenId);

    /**
     * @dev Error emitted when a name cannot be reduced in expiration.
     */
    error CannotReduceExpiration(uint64 oldExpiration, uint64 newExpiration);

    /**
     * @dev Error emitted when a name cannot be set to a past expiration.
     */
    error CannotSetPastExpiration(uint64 expiry);

    /**
     * @dev Event emitted when a name is renewed.
     */
    event NameRenewed(uint256 indexed tokenId, uint64 newExpiration, address renewedBy);

    /**
     * @dev Event emitted when a name is burned.
     */
    event NameBurned(uint256 indexed tokenId, address burnedBy);

    /**
     * @dev Registers a new name.
     * @param label The label to register.
     * @param owner The address of the owner of the name.
     * @param registry The registry to set as the name.
     * @param resolver The resolver to set for the name.
     * @param roleBitmap The role bitmap to set for the name.
     * @param expires The expiration date of the name.
     */
    function register(string calldata label, address owner, IRegistry registry, address resolver, uint256 roleBitmap, uint64 expires) external returns (uint256 tokenId);

    /**
     * @dev Renews a name.
     * @param tokenId The token ID of the name to renew.
     * @param expires The expiration date of the name.
     */ 
    function renew(uint256 tokenId, uint64 expires) external;

    /**
     * @dev Burns a name.
     * @param tokenId The token ID of the name to burn.
     */
    function burn(uint256 tokenId) external;

    /**
     * @dev Sets a name.
     * @param tokenId The token ID of the name to set.
     * @param registry The registry to set as the name.
     */
    function setSubregistry(uint256 tokenId, IRegistry registry) external;

    /**
     * @dev Sets a resolver for a name.
     * @param tokenId The token ID of the name to set a resolver for.
     * @param resolver The resolver to set for the name.
     */
    function setResolver(uint256 tokenId, address resolver) external;

    /**
     * @dev Fetches the expiry date of a name.
     * @param tokenId The token ID of the name to fetch the expiry for.
     * @return The expiry date of the name.
     */
    function getExpiry(uint256 tokenId) external view returns (uint64);
}