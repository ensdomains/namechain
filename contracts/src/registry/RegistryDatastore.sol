// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IRegistryDatastore} from "./IRegistryDatastore.sol";
import {NameUtils} from "../utils/NameUtils.sol";

contract RegistryDatastore is IRegistryDatastore {
    mapping(address registry => mapping(uint256 labelHash => uint256)) internal subregistries;
    mapping(address registry => mapping(uint256 labelHash => uint256)) internal resolvers;

    function getSubregistry(address registry, uint256 labelHash)
        public
        view
        returns (address subregistry, uint64 expiry, uint32 data)
    {
        uint256 blob = subregistries[registry][NameUtils.getCanonicalId(labelHash)];
        subregistry = address(uint160(blob));
        expiry = uint64(blob >> 160);
        data = uint32(blob >> 224);
    }

    function getSubregistry(uint256 labelHash) external view returns (address subregistry, uint64 expiry, uint32 data) {
        return getSubregistry(msg.sender, labelHash);
    }

    function getResolver(address registry, uint256 labelHash) public view returns (address resolver, uint64 expiry, uint32 data) {
        uint256 blob = resolvers[registry][NameUtils.getCanonicalId(labelHash)];
        resolver = address(uint160(blob));
        expiry = uint64(blob >> 160);
        data = uint32(blob >> 224);
    }

    function getResolver(uint256 labelHash) external view returns (address resolver, uint64 expiry, uint32 data) {
        return getResolver(msg.sender, labelHash);
    }

    function setSubregistry(uint256 labelHash, address subregistry, uint64 expiry, uint32 data) external {
        uint256 canonicalLabelHash = NameUtils.getCanonicalId(labelHash);
        subregistries[msg.sender][canonicalLabelHash] = (uint256(data) << 224) | (uint256(expiry) << 224) | uint256(uint160(subregistry));
        emit SubregistryUpdate(msg.sender, canonicalLabelHash, subregistry, expiry, data);
    }

    function setResolver(uint256 labelHash, address resolver, uint64 expiry, uint32 data) external {
        uint256 canonicalLabelHash = NameUtils.getCanonicalId(labelHash);
        resolvers[msg.sender][canonicalLabelHash] = (uint256(data) << 224) | (uint256(expiry) << 160) | uint256(uint160(resolver));
        emit ResolverUpdate(msg.sender, canonicalLabelHash, resolver, expiry, data);
    }
}
