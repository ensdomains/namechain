// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IRegistryDatastore} from "./IRegistryDatastore.sol";
import {NameUtils} from "./NameUtils.sol";

contract RegistryDatastore is IRegistryDatastore {
    mapping(address registry => mapping(uint256 id => uint256)) internal subregistries;
    mapping(address registry => mapping(uint256 id => uint256)) internal resolvers;

    function getSubregistry(address registry, uint256 id)
        public
        view
        returns (address subregistry, uint64 expiry, uint32 data)
    {
        uint256 blob = subregistries[registry][NameUtils.getCanonicalId(id)];
        subregistry = address(uint160(blob));
        expiry = uint64(blob >> 160);
        data = uint32(blob >> 224);
    }

    function getSubregistry(uint256 id) external view returns (address subregistry, uint64 expiry, uint32 data) {
        return getSubregistry(msg.sender, id);
    }

    function getResolver(address registry, uint256 id) public view returns (address resolver, uint64 expiry, uint32 data) {
        uint256 blob = resolvers[registry][NameUtils.getCanonicalId(id)];
        resolver = address(uint160(blob));
        expiry = uint64(blob >> 160);
        data = uint32(blob >> 224);
    }

    function getResolver(uint256 id) external view returns (address resolver, uint64 expiry, uint32 data) {
        return getResolver(msg.sender, id);
    }

    function setSubregistry(uint256 id, address subregistry, uint64 expiry, uint32 data) external {
        id = NameUtils.getCanonicalId(id);
        subregistries[msg.sender][id] = (uint256(data) << 224) | (uint256(expiry) << 160) | uint256(uint160(subregistry));
        emit SubregistryUpdate(msg.sender, id, subregistry, expiry, data);
    }

    function setResolver(uint256 id, address resolver, uint64 expiry, uint32 data) external {
        id = NameUtils.getCanonicalId(id);
        resolvers[msg.sender][id] = (uint256(data) << 224) | (uint256(expiry) << 160) | uint256(uint160(resolver));
        emit ResolverUpdate(msg.sender, id, resolver, expiry, data);
    }
}
