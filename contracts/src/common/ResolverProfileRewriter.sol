// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IMulticallable} from "@ens/contracts/resolvers/IMulticallable.sol";

library ResolverProfileRewriter {
    function replaceNode(
        bytes calldata data,
        bytes32 node
    ) internal pure returns (bytes memory copy) {
        copy = data;
        if (bytes4(data) == IMulticallable.multicall.selector) {
            assembly {
                let off := add(copy, 36)
                off := add(off, mload(off))
                let size := shl(5, mload(off))
                // prettier-ignore
                for { } size { size := sub(size, 32) } {
                    mstore(add(add(off, 68), mload(add(off, size))), node)
                }
            }
            // uint256 offset = 4 + uint256(bytes32(data[4:]));
            // uint256 count = uint256(bytes32(data[offset:]));
            // offset += 32;
            // for (uint256 i; i < count; ++i) {
            //     uint256 offset2 = uint256(bytes32(data[offset + (i << 5):]));
            //     assembly {
            //         mstore(add(add(copy, offset), add(offset2, 68)), node)
            //     }
            // }
        } else {
            assembly {
                mstore(add(copy, 36), node)
            }
        }
    }
}