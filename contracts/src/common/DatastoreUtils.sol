// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

library DatastoreUtils {
    /// @dev Pack (address, expiry, data) together into a word.
    /// @param addr The address to pack.
    /// @param expiry The expiry to pack.
    /// @param data The data to pack.
    /// @return packed The packed data.
    function pack(
        address addr,
        uint64 expiry,
        uint32 data
    ) internal pure returns (uint256 packed) {
        packed =
            (uint256(data) << 224) |
            (uint256(expiry) << 160) |
            uint256(uint160(addr));
    }

    /// @dev Unpack a word into (address, expiry, data).
    /// @param packed The packed data.
    /// @return addr The packed address.
    /// @return expiry The packed expiry.
    /// @return data The packed data.
    function unpack(
        uint256 packed
    ) internal pure returns (address addr, uint64 expiry, uint32 data) {
        addr = address(uint160(packed));
        expiry = uint64(packed >> 160);
        data = uint32(packed >> 224);
    }
}
