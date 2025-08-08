// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

library ResolverProfileRewriter {
    /// @dev Replace the node in the calldata with a new node.
    ///      Supports `multicall()` to arbirary depth.
    /// @param call The calldata for a resolver.
    /// @param node The replacement node.
    /// @return copy A copy of the calldata with node replaced.
    function replaceNode(
        bytes calldata call,
        bytes32 node
    ) internal pure returns (bytes memory copy) {
        copy = call; // make a copy
        assembly {
            function replace(ptr, _node) {
                switch shr(224, mload(add(ptr, 32))) // call selector
                case 0xac9650d8 {
                    // multicall (bytes[])
                    let off := add(ptr, 36)
                    off := add(off, mload(off))
                    let size := shl(5, mload(off))
                    // prettier-ignore
                    for { } size { size := sub(size, 32) } {
                        replace(add(add(off, 32), mload(add(off, size))), _node)
                    }
                }
                default {
                    mstore(add(ptr, 36), _node) // replace node
                }
            }
            replace(copy, node)
        }
    }
}
