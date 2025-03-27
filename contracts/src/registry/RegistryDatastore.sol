// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IRegistryDatastore} from "./IRegistryDatastore.sol";

contract RegistryDatastore is IRegistryDatastore {
    uint256 LABEL_HASH_MASK = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000;
    mapping(address registry => mapping(uint256 labelHash => uint256)) internal subregistries;
    mapping(address registry => mapping(uint256 labelHash => uint256)) internal resolvers;

    function getSubregistry(address registry, uint256 labelHash)
        public
        view
        returns (address subregistry, uint64 expiry)
    {
        uint256 data = subregistries[registry][labelHash & LABEL_HASH_MASK];
        subregistry = address(uint160(data));
        expiry = uint64(data >> 160);
    }

    function getSubregistry(uint256 labelHash) external view returns (address subregistry, uint64 expiry) {
        return getSubregistry(msg.sender, labelHash);
    }

    function getResolver(address registry, uint256 labelHash) public view returns (address resolver, uint64 expiry) {
        uint256 data = resolvers[registry][labelHash & LABEL_HASH_MASK];
        resolver = address(uint160(data));
        expiry = uint64(data >> 160);
    }

    function getResolver(uint256 labelHash) external view returns (address resolver, uint64 expiry) {
        return getResolver(msg.sender, labelHash);
    }

    function setSubregistry(uint256 labelHash, address subregistry, uint64 expiry) external {
        subregistries[msg.sender][labelHash & LABEL_HASH_MASK] = (uint256(expiry) << 160) | uint256(uint160(subregistry));
        emit SubregistryUpdate(msg.sender, labelHash & LABEL_HASH_MASK, subregistry, expiry);
    }

    function setResolver(uint256 labelHash, address resolver, uint64 expiry) external {
        resolvers[msg.sender][labelHash & LABEL_HASH_MASK] = (uint256(expiry) << 160) | uint256(uint160(resolver));
        emit ResolverUpdate(msg.sender, labelHash & LABEL_HASH_MASK, resolver, expiry);
    }
}
