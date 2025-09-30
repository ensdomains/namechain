// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IRegistryDatastore} from "./IRegistryDatastore.sol";
import {NameUtils} from "./NameUtils.sol";

contract RegistryDatastore is IRegistryDatastore {
    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    mapping(address registry => mapping(uint256 id => Entry)) private _entries;

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    function setEntry(address registry, uint256 id, Entry calldata entry) external {
        _entries[registry][NameUtils.getCanonicalId(id)] = entry;
    }

    function setSubregistry(uint256 id, address subregistry) external {
        _entries[msg.sender][NameUtils.getCanonicalId(id)].subregistry = subregistry;
    }

    function setResolver(uint256 id, address resolver) external {
        _entries[msg.sender][NameUtils.getCanonicalId(id)].resolver = resolver;
    }

    function getEntry(address registry, uint256 id) external view returns (Entry memory) {
        return _entries[registry][NameUtils.getCanonicalId(id)];
    }
}
