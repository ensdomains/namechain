// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/// @dev Library to wrap and unwrap error data inside of `Error(string)`.
library WrappedErrorLib {
    bytes4 public constant ERROR_STRING_SELECTOR = 0x08c379a0; // Error(string)

    bytes4 public constant WRAPPED_ERROR_SELECTOR = unicode"❌("; // TODO: decide this

    /// @dev Wrap an error and then revert.
    function wrapAndRevert(bytes memory err) internal pure {
        err = wrap(err);
        assembly ("memory-safe") {
            revert(add(err, 32), mload(err))
        }
    }

    /// @dev Embed a typed error into `Error(string)`.
    ///      Does nothing if already `Error(string)`.
    ///      For detection, `WRAPPED_ERROR_SELECTOR` is the first 4-bytes of the error string.
    function wrap(bytes memory err) internal pure returns (bytes memory) {
        if (err.length > 0 && bytes4(err) != ERROR_STRING_SELECTOR) {
            // assert((err.length & 31) == 4);
            unchecked {
                // uint256 n = 4; // leave room for selector
                // bytes memory v = new bytes(n + (err.length << 1));
                // for (uint256 i; i < err.length; ++i) {
                //     bytes1 cp = err[i];
                //     // encode byte as utf8 codepoints
                //     if (cp < 0x80) {
                //         v[n++] = cp;
                //     } else {
                //         v[n++] = bytes1(0xC0 | (uint8(cp) >> 6));
                //         v[n++] = bytes1(0x80 | (uint8(cp) & 0x3F));
                //     }
                // }
                // uint256 word = uint32(WRAPPED_ERROR_SELECTOR);
                // assembly ("memory-safe") {
                //     mstore(add(v, 4), word)
                //     mstore(v, n) // truncate
                // }
                // err = abi.encodeWithSelector(ERROR_STRING_SELECTOR, v);
                err = abi.encodeWithSelector(
                    ERROR_STRING_SELECTOR,
                    abi.encodePacked(WRAPPED_ERROR_SELECTOR, err)
                );
            }
        }
        return err;
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
            v = abi.decode(v, (bytes));
            if (bytes4(v) == WRAPPED_ERROR_SELECTOR) {
                assembly {
                    mstore(add(v, 4), sub(mload(v), 4))
                    v := add(v, 4) // skip 4 bytes
                }
                // uint256 n; // decode bytes as utf8 codepoints
                // for (uint256 i; i < v.length; ++i) {
                //     uint8 x = uint8(v[i]);
                //     if (x < 0x80) {
                //         v[n++] = bytes1(x);
                //     } else {
                //         v[n++] = bytes1((uint8(x & 31) << 6) | (uint8(v[++i]) & 63));
                //     }
                // }
                // assembly ("memory-safe") {
                //     mstore(v, n)
                // }
                err = v;
            }
        }
        return err;
    }
}
