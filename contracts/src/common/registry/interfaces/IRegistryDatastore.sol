// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/**
 * @dev Interface for the ENSv2 registry datastore, which stores subregistry and resolver addresses and other data
 *      for all names, keyed by registry address and label hash.
 */
interface IRegistryDatastore {
    ////////////////////////////////////////////////////////////////////////
    // Events
    ////////////////////////////////////////////////////////////////////////

    /**
     * @dev Emitted when a new unique subregistry address is set in the datastore
     * @param registry The address of the new subregistry
     */
    event NewRegistry(address indexed registry);

    ////////////////////////////////////////////////////////////////////////
    // Types
    ////////////////////////////////////////////////////////////////////////

    struct Entry {
        uint64 expiry;
        uint32 tokenVersionId;
        address subregistry;
        uint32 eacVersionId;
        address resolver;
    }

    ////////////////////////////////////////////////////////////////////////
    // Functions
    ////////////////////////////////////////////////////////////////////////

    function newRegistry(address registry) external;

    function setEntry(uint256 id, Entry calldata entry) external;

    function getEntry(address registry, uint256 id) external view returns (Entry calldata);
}
