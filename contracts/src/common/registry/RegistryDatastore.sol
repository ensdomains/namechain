// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {LibLabel} from "../utils/LibLabel.sol";

import {IRegistryDatastore} from "./interfaces/IRegistryDatastore.sol";

contract RegistryDatastore is IRegistryDatastore {
    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    mapping(address registry => mapping(uint256 id => Entry)) private _entries;

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    function setEntry(uint256 id, Entry calldata entry) external {
        _entries[msg.sender][LibLabel.getCanonicalId(id)] = entry;
    }

    function setSubregistry(uint256 id, address subregistry) external {
        _entries[msg.sender][LibLabel.getCanonicalId(id)].subregistry = subregistry;
    }

    function setResolver(uint256 id, address resolver) external {
        _entries[msg.sender][LibLabel.getCanonicalId(id)].resolver = resolver;
    }

    function setExpiry(uint256 id, uint64 expiry) external {
        _entries[msg.sender][LibLabel.getCanonicalId(id)].expiry = expiry;
    }

    function getEntry(address registry, uint256 id) external view returns (Entry memory) {
        return _entries[registry][LibLabel.getCanonicalId(id)];
    }
}
