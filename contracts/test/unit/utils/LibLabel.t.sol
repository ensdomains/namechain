// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, contracts-v2/ordering, one-contract-per-file

import {Test} from "forge-std/Test.sol";

import {LibLabel} from "~src/utils/LibLabel.sol";

contract LibLabelTest is Test {
    function test_known() external pure {
        uint256 id = LibLabel.id("abc");
        assertEq(id, 0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45);
        assertEq(
            LibLabel.canonicalId(id),
            0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58f00000000
        );
    }

    function test_id(string memory label) external pure {
        assertEq(LibLabel.id(label), uint256(keccak256(bytes(label))));
    }

    function test_canonicalId(uint256 id) external pure {
        uint256 canonicalId = LibLabel.canonicalId(id);
        assertEq(canonicalId, id ^ uint32(id), "xor");
        assertEq(canonicalId, id - uint32(id), "sub");
        assertEq(canonicalId, id & ~uint256(0xffffffff), "and");
        assertEq(canonicalId, (id >> 32) << 32, "shift");
    }

    function test_collisions(string memory A, string memory B) external pure {
        uint256 a = LibLabel.id(A);
        uint256 b = LibLabel.id(B);
        if (a != b && LibLabel.canonicalId(a) == LibLabel.canonicalId(b)) {
            assertEq(A, B);
        }
    }
}
