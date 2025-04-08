// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

library DatastoreUtils {
    uint256 constant LABEL_HASH_MASK = ~uint256(0xFFFFFFFF);

    /// @dev Normalize a labelHash.
    ///      Effectively zeros the lower 32-bits.
    /// @param unnormalized The unnormalized labelHash.
    /// @return normalized The normalized labelHash.
    function normalizeLabelHash(
        uint256 unnormalized
    ) internal pure returns (uint256 normalized) {
        normalized = unnormalized & LABEL_HASH_MASK;
    }

    /// @dev Pack (address, flags) together into a word.
    /// @param addr The address to pack.
    /// @param flags The flags to pack.
    /// @return packed The packed data.
    function pack(
        address addr,
        uint96 flags
    ) internal pure returns (uint256 packed) {
        packed = (uint256(flags) << 160) | uint160(addr);
    }

    /// @dev Unpack a word into (address, flags).
    /// @param packed The packed data.
    /// @return addr The packed address.
    /// @return flags The packed flags.
    function unpack(
        uint256 packed
    ) internal pure returns (address addr, uint96 flags) {
        addr = address(uint160(packed));
        flags = uint96(packed >> 160);
    }
}
