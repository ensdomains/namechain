// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IRegistryDatastore} from "./IRegistryDatastore.sol";
import {NameUtils} from "./NameUtils.sol";

contract RegistryDatastore is IRegistryDatastore {
    mapping(address registry => mapping(uint256 id => Entry)) entries;

    function getEntry(address registry, uint256 id)
        external
        view
        returns (Entry memory)
    {
        return entries[registry][NameUtils.getCanonicalId(id)];
    }


    function setEntry(address registry, uint256 id, Entry calldata entry)
        external
    {
        entries[registry][NameUtils.getCanonicalId(id)] = entry;
    }

    function setSubregistry(uint256 id, address subregistry) external {
        entries[msg.sender][NameUtils.getCanonicalId(id)].subregistry = subregistry;
    }

    function setResolver(uint256 id, address resolver) external {
        entries[msg.sender][NameUtils.getCanonicalId(id)].resolver = resolver;
    }
}
