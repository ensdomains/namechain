// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IERC1155Singleton} from "../../erc1155/interfaces/IERC1155Singleton.sol";

interface IRegistry is IERC1155Singleton {
    ////////////////////////////////////////////////////////////////////////
    // Events
    ////////////////////////////////////////////////////////////////////////

    /**
     * @dev SHOULD be emitted when a new label is registered
     */
    event NameRegistered(
        uint256 indexed tokenId,
        string label,
        uint64 expiration,
        address registeredBy
    );

    /**
     * @dev Event emitted when a name is renewed.
     */
    event NameRenewed(uint256 indexed tokenId, uint64 newExpiration, address renewedBy);

    /**
     * @dev Event emitted when a name is burned.
     */
    event NameBurned(uint256 indexed tokenId, address burnedBy);

    /**
     * @dev Event emitted when a subregistry is updated.
     */
    event SubregistryUpdate(uint256 indexed id, address subregistry);

    /**
     * @dev Event emitted when a resolver is updated.
     */
    event ResolverUpdate(uint256 indexed id, address resolver);

    /**
     * @dev Event emitted when a token is regenerated with a new token ID.
     *      This occurs when roles are granted or revoked to maintain ERC1155 compliance.
     */
    event TokenRegenerated(uint256 oldTokenId, uint256 newTokenId);

    ////////////////////////////////////////////////////////////////////////
    // Functions
    ////////////////////////////////////////////////////////////////////////

    /**
     * @dev Fetches the registry for a subdomain.
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
}
