// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IMulticallable} from "@ens/contracts/resolvers/IMulticallable.sol";

library ResolverProfileRewriter {
    /// @dev Replace the node in the calldata with a new node.
    ///      Supports `multicall()`.
    /// @param call The calldata.
    /// @param node The replacement node.
    /// @return copy A copy of the calldata with node replaced.
    function replaceNode(
        bytes calldata call,
        bytes32 node
    ) internal pure returns (bytes memory copy) {
        copy = call;
        if (bytes4(call) == IMulticallable.multicall.selector) {
            assembly {
                let off := add(copy, 36)
                off := add(off, mload(off))
                let size := shl(5, mload(off))
                // prettier-ignore
                for { } size { size := sub(size, 32) } {
                    mstore(add(add(off, 68), mload(add(off, size))), node)
                }
            }
        } else {
            assembly {
                mstore(add(copy, 36), node)
            }
        }
        // assembly {
        //     function replace(ptr, _node) {
        //         switch shr(224, mload(add(ptr, 32)))
        //         case 0xac9650d8 {
        //             let off := add(ptr, 36)
        //             off := add(off, mload(off))
        //             let size := shl(5, mload(off))
        //             for { } size { size := sub(size, 32) } {
        //                 replace(add(add(off, 32), mload(add(off, size))), _node)
        //             }
        //         }
        //         default {
        //             mstore(add(ptr, 36), _node)
        //         }
        //     }
        //     replace(copy, node)
        // }
    }
}
