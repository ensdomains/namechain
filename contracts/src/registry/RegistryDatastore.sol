// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IRegistryDatastore} from "./IRegistryDatastore.sol";

contract RegistryDatastore is IRegistryDatastore {
    struct LabelData{
        uint96 flags;
        address subregistry;
        address resolver;
    }

    uint256 LABEL_HASH_MASK = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000;

    mapping(address registry => mapping(uint256 labelHash => LabelData)) internal data;

    function getSubregistry(address registry, uint256 labelHash)
        public
        view
        returns (address subregistry, uint96 flags)
    {
        LabelData storage labelData = data[registry][labelHash & LABEL_HASH_MASK];
        subregistry = labelData.subregistry;
        flags = labelData.flags;
    }

    function getSubregistry(uint256 labelHash) external view returns (address subregistry, uint96 flags) {
        return getSubregistry(msg.sender, labelHash);
    }

    function getResolver(address registry, uint256 labelHash) public view returns (address resolver, uint96 flags) {
        LabelData storage labelData = data[registry][labelHash & LABEL_HASH_MASK];
        resolver = labelData.resolver;
        flags = labelData.flags;
    }

    function getResolver(uint256 labelHash) external view returns (address resolver, uint96 flags) {
        return getResolver(msg.sender, labelHash);
    }

    function setSubregistry(uint256 labelHash, address subregistry, uint96 flags) external {
        uint256 labelHashWithMask = labelHash & LABEL_HASH_MASK;
        data[msg.sender][labelHashWithMask].subregistry = subregistry;
        data[msg.sender][labelHashWithMask].flags = flags;
        emit SubregistryUpdate(msg.sender, labelHashWithMask, subregistry, flags);
    }

    function setResolver(uint256 labelHash, address resolver, uint96 flags) external {
        uint256 labelHashWithMask = labelHash & LABEL_HASH_MASK;
        data[msg.sender][labelHashWithMask].resolver = resolver;
        data[msg.sender][labelHashWithMask].flags = flags;
        emit ResolverUpdate(msg.sender, labelHashWithMask, resolver, flags);
    }
}
