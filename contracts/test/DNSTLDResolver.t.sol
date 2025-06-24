// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";
import {DNSTLDResolver} from "../src/L1/DNSTLDResolver.sol";
import {DNSSEC} from "@ens/contracts/dnssec-oracle/DNSSEC.sol";
import {IUniversalResolver} from "@ens/contracts/universalResolver/IUniversalResolver.sol";
import {HexUtils} from "@ens/contracts/utils/HexUtils.sol";

contract MockUR is IUniversalResolver {
    address immutable resolver;
    constructor(uint160 x) {
        resolver = address(x);
    }
    function findResolver(
        bytes memory
    ) public view override returns (address, bytes32, uint256) {
        return (resolver, bytes32(uint256(1)), 0);
    }
    function resolve(
        bytes calldata,
        bytes calldata data
    ) external view returns (bytes memory, address) {
        return (data, resolver);
    }
    function reverse(
        bytes calldata addrBytes,
        uint256 coinType
    ) external view returns (string memory, address, address) {}
}

contract MockDNS is DNSTLDResolver {
    constructor()
        DNSTLDResolver(
            new MockUR(1),
            new MockUR(2),
            DNSSEC(address(0)),
            new string[](0)
        )
    {}
    function readTXT(bytes memory v) external pure returns (bytes memory) {
        return _readTXT(v, 0, v.length);
    }
    function readTXT(bytes memory v, uint256 pos, uint256 end) external pure returns (bytes memory) {
        return _readTXT(v, pos, end);
    }
    function trim(bytes memory v) external pure returns (bytes memory) {
        return _trim(abi.encodePacked(v));
    }
    function parseResolver(bytes memory v) external view returns (address) {
        return _parseResolver(v);
    }
}

contract DNSTLDResolverTest is Test {
    MockDNS dns;

    function setUp() external {
        dns = new MockDNS();
    }

    function test_readTXT() external view {
        assertEq(dns.readTXT(""), "");
        assertEq(dns.readTXT("\x01a"), "a");
        assertEq(dns.readTXT("\x00\x01a"), "a");
        assertEq(dns.readTXT("\x01a\x01b"), "ab");
    }

    function test_readTXT_invalid() external {
        vm.expectRevert();
        dns.readTXT("\x01");
        vm.expectRevert();
        dns.readTXT("\x01a\x01");
        vm.expectRevert();
        dns.readTXT("\x00a");
    }

    function testFuzz_readTXT(uint16 pad) external {
        bytes memory v = new bytes(pad);
        bytes memory u;
        for (uint256 i = vm.randomUint(5); i > 0; i--) {
            bytes memory rng = vm.randomBytes(vm.randomUint(0, 255));
            v = abi.encodePacked(v, uint8(rng.length), rng);
            u = abi.encodePacked(u, rng);
        }
        assertEq(dns.readTXT(v, pad, v.length), u);
    }

    function test_trim() external view {
        assertEq(dns.trim("a"), "a");
        assertEq(dns.trim("a  "), "a");
        assertEq(dns.trim("  a"), "a");
        assertEq(dns.trim(" a "), "a");
    }

    function testFuzz_trim(uint8 na, uint8 nb, uint8 n) external view {
        bytes memory a = new bytes(na);
        for (uint256 i; i < na; i++) a[i] = " ";
        bytes memory b = new bytes(nb);
        for (uint256 i; i < nb; i++) b[i] = " ";
        bytes memory v = new bytes(n);
        assertEq(dns.trim(abi.encodePacked(a, v, b)), v);
    }

    function test_parseResolver() external view {
        assertEq(dns.parseResolver("0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e"), 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e);
        assertEq(dns.parseResolver("vitalik.eth"), address(2));
    }

    function testFuzz_parseResolver_address(address a) external view {
        assertEq(dns.parseResolver(abi.encodePacked("0x", HexUtils.addressToHex(a))), a);
    }

}
