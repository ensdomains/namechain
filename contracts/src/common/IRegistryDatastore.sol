// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/**
 * @dev Interface for the ENSv2 registry datastore, which stores subregistry and resolver addresses and flags
 *      for all names, keyed by registry address and label hash.
 *      The lower 32 bits of label hashes are masked out for storage and retrieval, allowing these bits to be used
 *      by registry implementations for different versions of tokens that reference the same underlying name. This
 *      means that two label hashes that differ only in the least-significant 32 bits will resolve to the same name.
 */
interface IRegistryDatastore {
    function getSubregistry(address registry, uint256 id)
        external
        view
        returns (address subregistry, uint64 expiry, uint32 data);
    function getSubregistry(uint256 id) external view returns (address subregistry, uint64 expiry, uint32 data);
    function getResolver(address registry, uint256 id) external view returns (address resolver, uint32 data);
    function getResolver(uint256 id) external view returns (address resolver, uint32 data);
    function setSubregistry(uint256 id, address subregistry, uint64 expiry, uint32 data) external;
    function setResolver(uint256 id, address resolver, uint32 data) external;
}
