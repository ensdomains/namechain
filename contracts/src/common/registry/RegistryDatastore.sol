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

    function newRegistry(address registry) external {
        emit NewRegistry(registry);
    }

    function setEntry(uint256 id, Entry calldata entry) external {
        _entries[msg.sender][LibLabel.getCanonicalId(id)] = entry;
    }

    function getEntry(address registry, uint256 id) external view returns (Entry memory) {
        return _entries[registry][LibLabel.getCanonicalId(id)];
    }
}
