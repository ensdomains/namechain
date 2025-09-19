// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import {NameUtils} from "../src/common/NameUtils.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

contract TestNameUtils is Test {
    function testFuzz_getCanonicalId(uint256 id) external pure {
        uint256 canonicalId = NameUtils.getCanonicalId(id);
        assertEq(canonicalId, id ^ uint32(id), "xor");
        assertEq(canonicalId, id - uint32(id), "sub");
        assertEq(canonicalId, id & ~uint256(0xffffffff), "and");
        assertEq(canonicalId, (id >> 32) << 32, "shift");
    }

    function testFuzz_labelToCanonicalId(string memory label) external pure {
        assertEq(
            NameUtils.labelToCanonicalId(label),
            NameUtils.getCanonicalId(uint256(keccak256(bytes(label))))
        );
    }

    function test_dnsEncodeEthLabel(uint8 len) external pure {
        vm.assume(len > 0); // NameCoder doesn't allow empty label
        string memory label = new string(len);
        assertEq(
            NameUtils.dnsEncodeEthLabel(label),
            NameCoder.encode(string.concat(label, ".eth"))
        );
    }
}
