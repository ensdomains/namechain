// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {HexUtils} from "@ens/contracts/utils/HexUtils.sol";

/// @dev Library to wrap and unwrap error data inside of `Error(string)`.
library WrappedErrorLib {
    bytes4 public constant ERROR_STRING_SELECTOR = 0x08c379a0; // Error(string)

    bytes16 public constant WRAPPED_ERROR_PREFIX = unicode"❌WrappedError(";

    /// @dev Wrap an error and then revert.
    function wrapAndRevert(bytes memory err) internal pure {
        err = wrap(err);
        // console.log("revert");
        // console.logBytes(err);
        assembly {
            revert(add(err, 32), mload(err))
        }
    }

    /// @dev Embed a typed error into `Error(string)`.
    ///      Does nothing if already `Error(string)`.
    ///      For detection, `WRAPPED_ERROR_PREFIX` is the first 4-bytes of the error string.
    function wrap(bytes memory err) internal pure returns (bytes memory) {
        if (err.length > 0 && bytes4(err) != ERROR_STRING_SELECTOR) {
            // assert((err.length & 31) == 4);
            err = abi.encodeWithSelector(
                ERROR_STRING_SELECTOR,
                encode(abi.encodePacked(WRAPPED_ERROR_PREFIX, err))
            );
        }
        return err;
    }

    function encode(bytes memory src) internal pure returns (bytes memory dst) {
        return bytes(HexUtils.bytesToHex(src));
        // dst = new bytes(src.length << 1);
        // uint256 n;
        // for (uint256 i; i < src.length; ++i) {
        //     bytes1 cp = src[i];
        //     // encode byte as utf8 codepoints
        //     if (cp < 0x80) {
        //         dst[n++] = cp;
        //     } else {
        //         dst[n++] = bytes1(0xC0 | (uint8(cp) >> 6));
        //         dst[n++] = bytes1(0x80 | (uint8(cp) & 0x3F));
        //     }
        // }
        // assembly {
        //     mstore(dst, n) // truncate
        // }
    }

    function decode(bytes memory src) internal pure returns (bytes memory dst) {
        (bytes memory v, bool ok) = HexUtils.hexToBytes(src, 0, src.length);
        return ok ? v : bytes("");
        // dst = new bytes(src.length);
        // uint256 n;
        // for (uint256 i; i < src.length; ++i) {
        //     bytes1 x = src[i];
        //     if (x < 0x80) {
        //         dst[n++] = x;
        //     } else {
        //         dst[n++] = bytes1(((uint8(x) & 31) << 6) | (uint8(src[++i]) & 63));
        //     }
        // }
        // assembly {
        //     mstore(dst, n)
        // }
    }

    /// @dev Unwrap a typed error from `Error(string)`.
    ///      Does nothing if detection fails.
    ///
    /// @param err The error data to unwrap.
    ///
    /// @return The unwrapped error data, or unmodified if not wrapped.
    function unwrap(bytes memory err) internal pure returns (bytes memory) {
        if (bytes4(err) == ERROR_STRING_SELECTOR) {
            bytes memory v = abi.encodePacked(err); // make a copy
            assembly {
                mstore(add(v, 4), sub(mload(v), 4))
                v := add(v, 4) // skip 4 bytes
            }
            v = decode(abi.decode(v, (bytes)));
            if (bytes16(v) == WRAPPED_ERROR_PREFIX) {
                assembly {
                    mstore(add(v, 16), sub(mload(v), 16))
                    v := add(v, 16) // skip 4 bytes
                }
                err = v;
            }
        }
        return err;
    }
}
