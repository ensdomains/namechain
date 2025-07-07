// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";
import {NameUtils} from "../src/common/NameUtils.sol";

contract TestNameUtils is Test {
    function test_isHashedLabel() external pure {
        assertFalse(NameUtils.isHashedLabel(""), "<empty>");
        assertFalse(NameUtils.isHashedLabel("[]"), "[]");
        assertFalse(NameUtils.isHashedLabel("[0x]"), "0x");

        assertFalse(
            NameUtils.isHashedLabel(
                "[0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcde]"
            ),
            "63"
        );
        assertFalse(
            NameUtils.isHashedLabel(
                "[0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdez]"
            ),
            "z"
        );
        assertFalse(
            NameUtils.isHashedLabel(
                "[0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0]"
            ),
            "65"
        );

        assertTrue(
            NameUtils.isHashedLabel(
                "[0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef]"
            ),
            "64"
        );
        assertTrue(
            NameUtils.isHashedLabel(
                "[0000000000000000000000000000000000000000000000000000000000000000]"
            ),
            "0"
        );
    }

    // function test_isValidLabel() external {
    //     assertFalse(NameUtils.isValidLabel(""), "0");
    //     assertFalse(NameUtils.isValidLabel(new string(256)), "256");

    //     assertTrue(NameUtils.isValidLabel(new string(1)), "1");
    //     assertTrue(NameUtils.isValidLabel(new string(255)), "255");
    // }

    function test_getCanonicalId() external pure {
        assertEq(NameUtils.getCanonicalId(0), 0);
        assertEq(NameUtils.getCanonicalId(0xFFFFFFFF), 0x00000000);
        assertEq(NameUtils.getCanonicalId(0x1FFFFFFFF), 0x100000000);
        assertEq(
            NameUtils.getCanonicalId(
                0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
            ),
            0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000
        );
    }

    function test_labelToCanonicalId() external pure {
        assertEq(
            NameUtils.labelToCanonicalId(""),
            0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad80400000000
        );
        assertEq(
            NameUtils.labelToCanonicalId("test"),
            0x9c22ff5f21f0b81b113e63f7db6da94fedef11b2119b4088b89664fb00000000
        );
        assertEq(
            NameUtils.labelToCanonicalId("eth"),
            0x4f5b812789fc606be1b3b16908db13fc7a9adf7ca72641f84d75b47000000000
        );
    }
}
