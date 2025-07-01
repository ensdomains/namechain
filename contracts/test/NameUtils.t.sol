// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";
import {NameUtils} from "../src/common/NameUtils.sol";

contract TestNameUtils is Test {
    function test_isHashedLabel() external {
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

    function test_isValidLabel() external {
        assertFalse(NameUtils.isValidLabel(""), "0");
        assertFalse(NameUtils.isValidLabel(new string(256)), "256");

        assertTrue(NameUtils.isValidLabel(new string(1)), "1");
        assertTrue(NameUtils.isValidLabel(new string(255)), "255");
    }

    function test_labelToCanonicalId() external {
        for (uint256 n = 1; n <= 255; n++) {
            assertEq(
                NameUtils.labelToCanonicalId(new string(n)),
                NameUtils.getCanonicalId(uint256(keccak256(new bytes(n))))
            );
        }
    }

    function testRevert_labelToCanonicalId_empty() external {
        vm.expectRevert();
        NameUtils.labelToCanonicalId("");
    }

    function testRevert_labelToCanonicalId_long() external {
        vm.expectRevert();
        NameUtils.labelToCanonicalId(new string(256));
    }

    function testRevert_labelToCanonicalId_hashed() external {
        vm.expectRevert();
        NameUtils.labelToCanonicalId(
            "[0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef]"
        );
    }
}
