// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IRegistryDatastore} from "./IRegistryDatastore.sol";
import {DatastoreUtils} from "./DatastoreUtils.sol";

contract RegistryDatastore is IRegistryDatastore {

    struct Entry {
        uint256 registryData;
        uint256 resolverData;
    }

    mapping(address registry => mapping(uint256 labelHash => Entry)) entries;

    function getSubregistry(
        address registry,
        uint256 labelHash
    ) public view returns (address subregistry, uint96 flags) {
        (subregistry, flags) = DatastoreUtils.unpack(
            entries[registry][DatastoreUtils.normalizeLabelHash(labelHash)].registryData
        );
    }

    function getSubregistry(
        uint256 labelHash
    ) external view returns (address subregistry, uint96 flags) {
        return getSubregistry(msg.sender, labelHash);
    }

    function getResolver(
        address registry,
        uint256 labelHash
    ) public view returns (address resolver, uint96 flags) {
        (resolver, flags) = DatastoreUtils.unpack(
            entries[registry][DatastoreUtils.normalizeLabelHash(labelHash)].resolverData
        );
    }

    function getResolver(
        uint256 labelHash
    ) external view returns (address resolver, uint96 flags) {
        return getResolver(msg.sender, labelHash);
    }

    function setSubregistry(
        uint256 labelHash,
        address subregistry,
        uint96 flags
    ) external {
        labelHash = DatastoreUtils.normalizeLabelHash(labelHash);
        entries[msg.sender][labelHash].registryData = DatastoreUtils.pack(subregistry, flags);
        emit SubregistryUpdate(msg.sender, labelHash, subregistry, flags);
    }

    function setResolver(
        uint256 labelHash,
        address resolver,
        uint96 flags
    ) external {
        labelHash = DatastoreUtils.normalizeLabelHash(labelHash);
        entries[msg.sender][labelHash].resolverData = DatastoreUtils.pack(resolver, flags);
        emit ResolverUpdate(msg.sender, labelHash, resolver, flags);
    }

}
