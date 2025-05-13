// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IRegistryDatastore} from "./IRegistryDatastore.sol";
import {DatastoreUtils} from "./DatastoreUtils.sol";
import {NameUtils} from "./NameUtils.sol";

contract RegistryDatastore is IRegistryDatastore {
    struct Entry {
        uint256 registryData;
        uint256 resolverData;
    }

    mapping(address registry => mapping(uint256 id => Entry)) entries;

    function getSubregistry(address registry, uint256 id)
        public
        view
        returns (address subregistry, uint64 expiry, uint32 data)
    {
        (subregistry, expiry, data) =
            DatastoreUtils.unpack(entries[registry][NameUtils.getCanonicalId(id)].registryData);
    }

    function getSubregistry(uint256 id) external view returns (address subregistry, uint64 expiry, uint32 data) {
        return getSubregistry(msg.sender, id);
    }

    function getResolver(address registry, uint256 id)
        public
        view
        returns (address resolver, uint64 expiry, uint32 data)
    {
        address resolverAddr;
        uint96 flags;
        (resolverAddr, flags) = DatastoreUtils.unpackWithFlags(entries[registry][NameUtils.getCanonicalId(id)].resolverData);
        // For backward compatibility, return 0 for expiry and the lower 32 bits of flags for data
        resolver = resolverAddr;
        expiry = 0;
        data = uint32(flags);
    }

    function getResolver(uint256 id) external view returns (address resolver, uint64 expiry, uint32 data) {
        return getResolver(msg.sender, id);
    }

    function setSubregistry(uint256 id, address subregistry, uint64 expiry, uint32 data) external {
        id = NameUtils.getCanonicalId(id);
        entries[msg.sender][id].registryData = DatastoreUtils.pack(subregistry, expiry, data);
        emit SubregistryUpdate(msg.sender, id, subregistry, expiry, data);
    }

    function setResolver(uint256 id, address resolver, uint32 data) external {
        id = NameUtils.getCanonicalId(id);
        // Convert the 32-bit data to a 96-bit flags field, preserving the data in the lower 32 bits
        uint96 flags = uint96(data);
        entries[msg.sender][id].resolverData = DatastoreUtils.packWithFlags(resolver, flags);
        emit ResolverUpdate(msg.sender, id, resolver, 0, data);
    }
}
