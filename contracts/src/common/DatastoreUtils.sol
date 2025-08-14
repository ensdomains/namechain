// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

library DatastoreUtils {
    /// @dev Pack `(address, data, expiry)` together into a word.
    /// @param addr The address to pack.
    /// @param data The data to pack.
    /// @param expiry The expiry to pack.
    /// @return packed The packed word.
    function pack(address addr, uint32 data, uint64 expiry) internal pure returns (uint256 packed) {
        packed = (uint256(expiry) << 192) | (uint256(data) << 160) | uint256(uint160(addr));
    }

    /// @dev Unpack a word into `(address, data, expiry)`.
    /// @param packed The packed word.
    /// @return addr The packed address.
    /// @return data The packed data.
    /// @return expiry The packed expiry.
    function unpack(uint256 packed) internal pure returns (address addr, uint32 data, uint64 expiry) {
        addr = address(uint160(packed));
        data = uint32(packed >> 160);
        expiry = uint64(packed >> 192);
    }
}
