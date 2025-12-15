// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IRegistry} from "./IRegistry.sol";

/**
 * @dev Interface for the ENSv2 registry datastore, which stores subregistry and resolver addresses and other data
 *      for all names, keyed by registry address and label hash.
 */
interface IRegistryDatastore {
    ////////////////////////////////////////////////////////////////////////
    // Types
    ////////////////////////////////////////////////////////////////////////

    struct Entry {
        uint64 expiry;
        uint32 tokenVersionId;
        IRegistry subregistry;
        uint32 eacVersionId;
        address resolver;
    }

    ////////////////////////////////////////////////////////////////////////
    // Functions
    ////////////////////////////////////////////////////////////////////////

    function setEntry(uint256 anyId, Entry calldata entry) external;

    function getEntry(IRegistry registry, uint256 anyId) external view returns (Entry calldata);
}
