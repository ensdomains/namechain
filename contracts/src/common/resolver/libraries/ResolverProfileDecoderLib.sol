// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IAddressResolver} from "@ens/contracts/resolvers/profiles/IAddressResolver.sol";
import {ITextResolver} from "@ens/contracts/resolvers/profiles/ITextResolver.sol";

/// @notice Library for safely decoding resolver calldata.
library ResolverProfileDecoderLib {
    /// @notice Check if calldata is `text(key)`.
    ///
    /// eg. `text("nick.eth", "avatar")`
    /// ```
    /// offset  calldata
    ///      0  59d1d43c                                                         = ITextResolver.text.selector
    ///      4  05a67c0ee82964c4f7394cdd47fee7f4d9503a23c09c38341779ea012afe6e00 = bytes32 node => namehash("nick.eth")
    ///     36  0000000000000000000000000000000000000000000000000000000000000040 = string(offset) => 64
    ///     68  0000000000000000000000000000000000000000000000000000000000000006 = string(length) => 6
    ///    100  6176617461720000000000000000000000000000000000000000000000000000 = "avatar"
    /// ```
    function isText(bytes memory data, bytes32 keyHash) internal pure returns (bool matched) {
        if (data.length >= 68 && bytes4(data) == ITextResolver.text.selector) {
            assembly {
                let ptr := add(data, 36) // ptr after selector
                let bound := add(add(ptr, mload(data)), 1) // end+1 for lt()
                ptr := add(ptr, mload(add(ptr, 32))) // string(offset)
                if lt(add(ptr, 32), bound) {
                    let len := mload(ptr) // string(length)
                    ptr := add(ptr, 32) // ptr after length
                    if lt(add(ptr, len), bound) {
                        matched := eq(keccak256(ptr, len), keyHash)
                    }
                }
            }
        }
    }

    /// @notice Check if calldata is `addr(coinType)`.
    ///
    /// eg. `addr("nick.eth", 60)`
    /// ```
    /// offset  calldata
    ///      0  f1cb7e06                                                         = IAddressResolver.text.selector
    ///      4  05a67c0ee82964c4f7394cdd47fee7f4d9503a23c09c38341779ea012afe6e00 = bytes32 node => namehash("nick.eth")
    ///     36  000000000000000000000000000000000000000000000000000000000000003c = uint256(coinType)
    /// ```
    function isAddr(bytes memory data, uint256 coinType) internal pure returns (bool matched) {
        if (data.length == 68 && bytes4(data) == IAddressResolver.addr.selector) {
            assembly {
                matched := eq(mload(add(data, 68)), coinType)
            }
        }
    }
}
