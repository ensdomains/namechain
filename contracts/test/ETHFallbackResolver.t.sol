// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";
import {
    ETHFallbackResolver,
    IBaseRegistrar,
    IUniversalResolver,
    IGatewayVerifier,
    NameCoder
} from "../src/L1/ETHFallbackResolver.sol";

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

    function countLabels(bytes calldata v) external pure returns (bytes32, uint256, uint256) {
        return _countLabels(v);
    }
}

contract TestETHFallbackResolver is Test {
    MockETHFallbackResolver efr;

    function setUp() external {
        efr = new MockETHFallbackResolver();
    }

    function _countLabels(string memory ens, uint256 expectCount, uint256 size2LD) internal view {
        bytes memory dns = NameCoder.encode(ens);
        (, uint256 count, uint256 offset) = efr.countLabels(dns);
        assertEq(count, expectCount, "count");
        assertEq(offset, expectCount > 0 ? dns.length - (6 + size2LD) : 0, "offset"); // u8(1) + u8(3) + "eth" + u8(0)
    }

    function test_countLabels_dotEth() external view {
        _countLabels("eth", 0, 0);
        _countLabels("aaaaa.eth", 1, 5);
        _countLabels("a.bbb.eth", 2, 3);
        _countLabels("a.b.c.eth", 3, 1);
    }

    function test_countLabels_notEth() external {
        vm.expectRevert();
        _countLabels("xyz", 0, 0);
        vm.expectRevert();
        _countLabels("chonk.box", 0, 0);
        vm.expectRevert();
        _countLabels("ens.domains", 0, 0);
    }

    function test_countlabels_invalid() external {
        vm.expectRevert();
        efr.countLabels(hex"");
        vm.expectRevert();
        efr.countLabels(hex"0000");
        vm.expectRevert();
        efr.countLabels(hex"0200");
    }

    function testFuzz_countLabels_dotEth(uint8 n) external {
        vm.assume(n < 10);
        uint256 size2LD = vm.randomUint(1, 255);
        string memory ens = string.concat(new string(size2LD), ".eth");
        for (uint256 i; i < n; i++) {
            ens = string.concat(new string(vm.randomUint(1, 255)), ".", ens);
        }
        _countLabels(ens, 1 + n, size2LD);
    }
}
