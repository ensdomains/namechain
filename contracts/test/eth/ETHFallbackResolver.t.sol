// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";
import {ETHFallbackResolver, IBaseRegistrar, IUniversalResolver, IGatewayVerifier, NameCoder, ETH_NODE} from "../../src/L1/ETHFallbackResolver.sol";

contract MockETHFallbackResolver is ETHFallbackResolver {
    constructor()
        ETHFallbackResolver(
            IBaseRegistrar(address(0)),
            IUniversalResolver(address(0)),
            address(0),
            address(0),
            IGatewayVerifier(address(0)),
            address(0),
            address(0)
        )
    {}

    function matchSuffix(
        bytes calldata name,
        bytes32 suffixNode
    ) external pure returns (bool, uint256, uint256) {
        return _matchSuffix(name, suffixNode);
    }
}

contract TestETHFallbackResolver is Test {
    MockETHFallbackResolver efr;

    function setUp() external {
        efr = new MockETHFallbackResolver();
    }

    function test_ETH_NODE() external view {
        assertEq(ETH_NODE, NameCoder.namehash(NameCoder.encode("eth"), 0));
    }

    function _assertMatch(
        string memory name,
        string memory nameSuffix,
        uint256 expectPrevOffset,
        uint256 expectOffset
    ) internal view {
        (bool matched, uint256 prevOffset, uint256 offset) = efr.matchSuffix(
            NameCoder.encode(name),
            NameCoder.namehash(NameCoder.encode(nameSuffix), 0)
        );
        assertTrue(matched, string(abi.encodePacked(name, "/", nameSuffix)));
        assertEq(
            prevOffset,
            expectPrevOffset,
            string(abi.encodePacked(name, "/", nameSuffix, " prevOffset"))
        );
        assertEq(
            offset,
            expectOffset,
            string(abi.encodePacked(name, "/", nameSuffix, " offset"))
        );
    }

    function _assertNoMatch(
        string memory name,
        string memory nameSuffix
    ) internal view {
        (bool matched, , ) = efr.matchSuffix(
            NameCoder.encode(name),
            NameCoder.namehash(NameCoder.encode(nameSuffix), 0)
        );
        assertFalse(matched, string(abi.encodePacked(name, "/", nameSuffix)));
    }

    function test_matchSuffix_same() external view {
        _assertMatch("", "", 0, 0);
        _assertMatch("eth", "eth", 0, 0);
        _assertMatch("a.b.c", "a.b.c", 0, 0);
    }

    function test_matchSuffix_dotEth() external view {
        _assertMatch("aaaaa.eth", "eth", 0, 6);
        _assertMatch("a.bbb.eth", "eth", 2, 6);
        _assertMatch("a.b.c.eth", "eth", 4, 6);
    }

    function test_matchSuffix_notEth() external view {
        _assertMatch("a.b.c.d", "b.c.d", 0, 2);
        _assertMatch("a.b.c.d", "c.d", 2, 4);
        _assertMatch("a.b.c.d", "d", 4, 6);
        _assertMatch("a.b.c.d", "", 6, 8);
    }

    function test_matchSuffix_noMatch() external view {
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
