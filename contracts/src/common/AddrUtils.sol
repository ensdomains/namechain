// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

library AddrUtils {
    /// @dev Cast `bytes` to `address`.
    ///      Applies 0-padding on left of 20 bytes then uses first 20 bytes.
    function toAddr(bytes memory a) internal pure returns (address addr) {
        return address(a.length < 20 ? bytes20(a) >> 3 << (20 - a.length) : bytes20(a));
    }

    // error InvalidEVMAddress(bytes addressBytes);
    //
    // /// @dev Cast `bytes` to `address`.
    // ///      Must be exactly 0 or 20 bytes.
    // function toAddr(bytes memory a) internal pure returns (address addr) {
    //     if (a.length == 20) {
    //         addr = address(bytes20(a));
    //     } else if (a.length != 0) {
    //         revert InvalidEVMAddress(a);
    //     }
    // }
}
