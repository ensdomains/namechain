// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

library NameMatcher {
    /// @dev Find the offset of `name` that hashes to `nodeSuffix`.
    /// @param name The name to search.
    /// @param nodeSuffix The node to match.
    /// @return matched True if name ends with the suffix.
    /// @return node The namehash of name.
    /// @return prevOffset The offset of the label before the suffix.
    /// @return suffixOffset The offset of name that hashes to the suffix.
    function suffix(
        bytes memory name,
        uint256 offset,
        bytes32 nodeSuffix
    )
        internal
        pure
        returns (
            bool matched,
            bytes32 node,
            uint256 prevOffset,
            uint256 suffixOffset
        )
    {
        (bytes32 labelHash, uint256 next) = NameCoder.readLabel(name, offset);
        if (labelHash != bytes32(0)) {
            (matched, node, prevOffset, suffixOffset) = suffix(
                name,
                next,
                nodeSuffix
            );
            if (node == nodeSuffix) {
                matched = true;
                prevOffset = offset;
                suffixOffset = next;
            }
            assembly {
                mstore(0, node)
                mstore(32, labelHash)
                node := keccak256(0, 64) // compute namehash()
            }
        }
        if (node == nodeSuffix) {
            matched = true;
        }
    }
}
