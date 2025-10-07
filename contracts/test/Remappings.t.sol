// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";

import {UnsafeCopyLib} from "~src/common/utils/UnsafeCopyLib.sol";

/// @dev Ensure remappings.txt is applied correctly.
///
/// Note: Forge does not recompile changes to file remappings as expected.
/// You must induce a recompile via clean or file change.
///
/// 1. Check UnsafeCopyLib is remapped to get `mcopy`.
///
contract RemappingsTest is Test {
    function test_UnsafeCopyLib() external pure {
        assertTrue(UnsafeCopyLib.REMAPPED);
    }
}
