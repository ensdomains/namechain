// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

library LibLabel {
    /// @notice Compute `labelhash(label)`.
    function id(string memory label) internal pure returns (uint256) {
        return uint256(keccak256(bytes(label)));
    }

    /// @notice Clear the lower 32-bits of `anyId`.
    /// @param anyId The labelhash, token ID, or resource.
    /// @return The canonical ID.
    function canonicalId(uint256 anyId) internal pure returns (uint256) {
        return anyId ^ uint32(anyId);
    }
}
