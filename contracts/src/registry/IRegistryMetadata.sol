// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/**
 * @dev Interface for providing metadata URIs for ENSv2 registry contracts.
 */
interface IRegistryMetadata {
    /**
     * @dev Fetches the token URI for a node.
     * @param tokenId The ID of the node to fetch a URI for.
     * @return The token URI for the node.
     */
    function tokenUri(uint256 tokenId) external view returns (string calldata);
}
