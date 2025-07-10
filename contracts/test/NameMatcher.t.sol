// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";
import {NameMatcher, NameCoder} from "../src/common/NameMatcher.sol";

contract TestNameMatcher is Test {
    function _assertMatch(
        string memory ensName,
        string memory ensNameSuffix,
        uint256 expectPrevOffset,
        uint256 expectOffset
    ) internal pure {
        bytes memory name = NameCoder.encode(ensName);
        (
            bool matched,
            bytes32 node,
            uint256 prevOffset,
            uint256 offset
        ) = NameMatcher.suffix(
                name,
                0,
                NameCoder.namehash(NameCoder.encode(ensNameSuffix), 0)
            );
        assertTrue(
            matched,
            string(abi.encodePacked(ensName, "/", ensNameSuffix))
        );
        assertEq(
            prevOffset,
            expectPrevOffset,
            string(abi.encodePacked(ensName, "/", ensNameSuffix, " prevOffset"))
        );
        assertEq(
            offset,
            expectOffset,
            string(abi.encodePacked(ensName, "/", ensNameSuffix, " offset"))
        );
        assertEq(
            node,
            NameCoder.namehash(name, 0),
            string(abi.encodePacked(ensName, "/", ensNameSuffix, " node"))
        );
    }

    function _assertNoMatch(
        string memory ensName,
        string memory ensNameSuffix
    ) internal pure {
        (bool matched, , , ) = NameMatcher.suffix(
            NameCoder.encode(ensName),
            0,
            NameCoder.namehash(NameCoder.encode(ensNameSuffix), 0)
        );
        assertFalse(
            matched,
            string(abi.encodePacked(ensName, "/", ensNameSuffix))
        );
    }

    function test_matchSuffix_same() external pure {
        _assertMatch("", "", 0, 0);
        _assertMatch("eth", "eth", 0, 0);
        _assertMatch("a.b.c", "a.b.c", 0, 0);
    }

    function test_matchSuffix_dotEth() external pure {
        _assertMatch("aaaaa.eth", "eth", 0, 6);
        _assertMatch("a.bbb.eth", "eth", 2, 6);
        _assertMatch("a.b.c.eth", "eth", 4, 6);
    }

    function test_matchSuffix_notEth() external pure {
        _assertMatch("a.b.c.d", "b.c.d", 0, 2);
        _assertMatch("a.b.c.d", "c.d", 2, 4);
        _assertMatch("a.b.c.d", "d", 4, 6);
        _assertMatch("a.b.c.d", "", 6, 8);
    }

    function test_matchSuffix_noMatch() external pure {
        _assertNoMatch("a", "b");
        _assertNoMatch("a", "a.b");
        _assertNoMatch("a", "b.a");
    }

    function testFuzz_matchSuffix_sub(
        uint256 a,
        uint256 b,
        uint256 c
    ) external {
        bytes memory vA = _randomName(bound(a, 1, 100));
        bytes memory vB = new bytes(bound(b, 1, 100));
        bytes memory vC = _randomName(bound(c, 1, 100));
        _assertMatch(
            string(abi.encodePacked(vA, ".", vB, ".", vC)),
            string(vC),
            vA.length + 1,
            vA.length + 2 + vB.length
        );
    }

    /// @dev Create valid name of length `n` with labels of random lengths.
    function _randomName(uint256 n) internal returns (bytes memory v) {
        v = new bytes(n);
        for (uint256 i; i < n; i++) v[i] = "a";
        for (uint256 i; i + 2 < n; i++) {
            i = vm.randomUint(i + 2, n - 1);
            v[i - 1] = ".";
        }
    }
}
