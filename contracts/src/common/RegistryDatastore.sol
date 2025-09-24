// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IRegistryDatastore} from "./IRegistryDatastore.sol";
import {NameUtils} from "./NameUtils.sol";

contract RegistryDatastore is IRegistryDatastore {
    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    struct Entry {
        uint256 registryData;
        uint256 resolverData;
    }

    mapping(address registry => mapping(uint256 id => Entry)) internal _entries;

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    function setSubregistry(
        uint256 id,
        address subregistry,
        uint64 expiry,
        uint32 data
    ) external {
        id = NameUtils.getCanonicalId(id);
        _entries[msg.sender][id].registryData = _pack(
            subregistry,
            data,
            expiry
        );
    }

    function setResolver(uint256 id, address resolver, uint32 data) external {
        id = NameUtils.getCanonicalId(id);
        _entries[msg.sender][id].resolverData = _pack(resolver, data, 0);
    }

    function getSubregistry(
        uint256 id
    ) external view returns (address subregistry, uint64 expiry, uint32 data) {
        return getSubregistry(msg.sender, id);
    }

    function getResolver(
        uint256 id
    ) external view returns (address resolver, uint32 data) {
        return getResolver(msg.sender, id);
    }

    function getSubregistry(
        address registry,
        uint256 id
    ) public view returns (address subregistry, uint64 expiry, uint32 data) {
        (subregistry, data, expiry) = _unpack(
            _entries[registry][NameUtils.getCanonicalId(id)].registryData
        );
    }

    function getResolver(
        address registry,
        uint256 id
    ) public view returns (address resolver, uint32 data) {
        address resolver_;
        // TODO: remove?
        uint64 expiry_;
        (resolver_, data, expiry_) = _unpack(
            _entries[registry][NameUtils.getCanonicalId(id)].resolverData
        );
        resolver = resolver_;
    }

    ////////////////////////////////////////////////////////////////////////
    // Internal functions
    ////////////////////////////////////////////////////////////////////////

    /// @dev Pack `(address, data, expiry)` together into a word.
    ///
    /// @param addr The address to pack.
    /// @param data The data to pack.
    /// @param expiry The expiry to pack.
    ///
    /// @return packed The packed word.
    function _pack(
        address addr,
        uint32 data,
        uint64 expiry
    ) internal pure returns (uint256 packed) {
        packed =
            (uint256(expiry) << 192) |
            (uint256(data) << 160) |
            uint256(uint160(addr));
    }

    /// @dev Unpack a word into `(address, data, expiry)`.
    ///
    /// @param packed The packed word.
    ///
    /// @return addr The packed address.
    /// @return data The packed data.
    /// @return expiry The packed expiry.
    function _unpack(
        uint256 packed
    ) internal pure returns (address addr, uint32 data, uint64 expiry) {
        addr = address(uint160(packed));
        data = uint32(packed >> 160);
        expiry = uint64(packed >> 192);
    }
}
