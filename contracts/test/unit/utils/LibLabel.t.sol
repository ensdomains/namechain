// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering, one-contract-per-file

import {Test} from "forge-std/Test.sol";

import {LibLabel} from "~src/utils/LibLabel.sol";

contract LibLabelTest is Test {
    function testFuzz_getCanonicalId(uint256 id) external pure {
        uint256 canonicalId = LibLabel.getCanonicalId(id);
        assertEq(canonicalId, id ^ uint32(id), "xor");
        assertEq(canonicalId, id - uint32(id), "sub");
        assertEq(canonicalId, id & ~uint256(0xffffffff), "and");
        assertEq(canonicalId, (id >> 32) << 32, "shift");
    }

    function testFuzz_labelToCanonicalId(string memory label) external pure {
        assertEq(
            LibLabel.labelToCanonicalId(label),
            LibLabel.getCanonicalId(uint256(keccak256(bytes(label))))
        );
    }
}
