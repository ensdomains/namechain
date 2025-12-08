// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

interface IOffchainResolverMetadataProvider {
    ////////////////////////////////////////////////////////////////////////
    // Events
    ////////////////////////////////////////////////////////////////////////
    event MetadataChanged(bytes name, string[] rpcURLs, uint256 chainId, address baseRegistry);

    /**
     * @dev Returns metadata for discovering the location of offchain name data
     * @param name DNS-encoded name to query
     * @return rpcURLs The JSON RPC endpoint for querying offchain data (optional, may be empty array)
     * @return chainId The chain ID where the data is stored (format for non-EVM systems to be determined)
     * @return baseRegistry The base registry address on the target chain that emits events (optional, may be zero address)
     */
    function metadata(
        bytes calldata name
    ) external view returns (string[] memory rpcURLs, uint256 chainId, address baseRegistry);
}
