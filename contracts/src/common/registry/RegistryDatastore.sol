// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {LibLabel} from "../utils/LibLabel.sol";

import {IRegistry} from "./interfaces/IRegistry.sol";
import {IRegistryDatastore} from "./interfaces/IRegistryDatastore.sol";

contract RegistryDatastore is IRegistryDatastore {
    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    mapping(IRegistry registry => mapping(uint256 canonicalId => Entry)) private _entries;

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    /// @inheritdoc IRegistryDatastore
    function setEntry(uint256 anyId, Entry calldata entry) external {
        _entries[IRegistry(msg.sender)][LibLabel.getCanonicalId(anyId)] = entry;
    }

    /// @inheritdoc IRegistryDatastore
    function getEntry(IRegistry registry, uint256 anyId) external view returns (Entry memory) {
        return _entries[registry][LibLabel.getCanonicalId(anyId)];
    }
}
