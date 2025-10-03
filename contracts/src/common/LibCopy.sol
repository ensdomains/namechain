//SPDX-License-Identifier: MIT
pragma solidity >=0.8.25;

library LibCopy {
    /// @dev Copy `mem[src:src+len]` to `mem[dst:dst+len]`.
    /// @param src The source memory offset.
    /// @param dst The destination memory offset.
    /// @param len The number of bytes to copy.
    function unsafeCopy(uint256 dst, uint256 src, uint256 len) internal pure {
        assembly {
            mcopy(dst, src, len)
        }
    }
}
