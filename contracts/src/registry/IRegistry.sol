// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IERC1155Singleton} from "./IERC1155Singleton.sol";

interface IRegistry is IERC1155Singleton {
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
     * @dev Event emitted when a name is relinquished.
     */
    event NameRelinquished(uint256 indexed tokenId, address relinquishedBy);

    /**
     * @dev SHOULD be emitted when a new label is registered
     */
    event NewSubname(uint256 indexed labelHash, string label);

    /**
     * @dev Fetches the registry for a subdomain of the current registry.
     * @param label The label to resolve.
     * @return The address of the registry for this subdomain, or `address(0)` if none exists.
     */
    function getSubregistry(string calldata label) external view returns (IRegistry);

    /**
     * @dev Fetches the resolver responsible for the specified label.
     * @param label The label to fetch a resolver for.
     * @return resolver The address of a resolver responsible for this name, or `address(0)` if none exists.
     */
    function getResolver(string calldata label) external view returns (address);

    /**
     * @dev Registers a new subdomain of the current registry.
     * @param label The label to register.
     * @param owner The address of the owner of the subdomain.
     * @param registry The registry to set as the subdomain.
     * @param resolver The resolver to set for the subdomain.
     * @param roleBitmap The role bitmap to set for the subdomain.
     * @param expires The expiration date of the subdomain.
     */
    function register(string calldata label, address owner, IRegistry registry, address resolver, uint256 roleBitmap, uint64 expires) external returns (uint256 tokenId);

    /**
     * @dev Renews a subdomain of the current registry.
     * @param tokenId The token ID of the subdomain to renew.
     * @param expires The expiration date of the subdomain.
     */ 
    function renew(uint256 tokenId, uint64 expires) external;

    /**
     * @dev Relinquishes a subdomain of the current registry.
     * @param tokenId The token ID of the subdomain to relinquish.
     */
    function relinquish(uint256 tokenId) external;

    /**
     * @dev Sets a subdomain of the current registry.
     * @param tokenId The token ID of the subdomain to set.
     * @param registry The registry to set as the subdomain.
     */
    function setSubregistry(uint256 tokenId, IRegistry registry) external;

    /**
     * @dev Sets a resolver for a subdomain of the current registry.
     * @param tokenId The token ID of the subdomain to set a resolver for.
     * @param resolver The resolver to set for the subdomain.
     */
    function setResolver(uint256 tokenId, address resolver) external;

    /**
     * @dev Fetches the expiry date of a subdomain of the current registry.
     * @param tokenId The token ID of the subdomain to fetch the expiry for.
     * @return The expiry date of the subdomain.
     */
    function getExpiry(uint256 tokenId) external view returns (uint64);

    /**
     * @dev Fetches the resource of a subdomain of the current registry.
     * @param tokenId The token ID of the subdomain to fetch the resource for.
     * @return The resource of the subdomain.
     */
    function tokenIdResource(uint256 tokenId) external view returns(bytes32);

    /**
     * @dev Fetches the token ID of a resource of the current registry.
     * @param resource The resource to fetch the token ID for.
     * @return The token ID of the resource.
     */
    function resourceTokenId(bytes32 resource) external view returns (uint256);
}