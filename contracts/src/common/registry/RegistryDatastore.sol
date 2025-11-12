// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {LibLabel} from "../utils/LibLabel.sol";

import {IRegistryDatastore} from "./interfaces/IRegistryDatastore.sol";

contract RegistryDatastore is IRegistryDatastore {
    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    mapping(address registry => mapping(uint256 id => Entry)) private _entries;
    mapping(address subregistry => bool) private _subregistrySeen;

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    function setEntry(uint256 id, Entry calldata entry) external {
        uint256 canonicalId = LibLabel.getCanonicalId(id);
        address oldSubregistry = _entries[msg.sender][canonicalId].subregistry;

        // Emit event only when subregistry changes to a new non-zero address
        if (
            entry.subregistry != address(0) && entry.subregistry != oldSubregistry
                && !_subregistrySeen[entry.subregistry]
        ) {
            _subregistrySeen[entry.subregistry] = true;
            emit NewRegistry(entry.subregistry);
        }

        _entries[msg.sender][canonicalId] = entry;
    }

    function getEntry(address registry, uint256 id) external view returns (Entry memory) {
        return _entries[registry][LibLabel.getCanonicalId(id)];
    }
}
