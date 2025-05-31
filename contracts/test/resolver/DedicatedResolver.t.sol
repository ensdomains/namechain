// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {DedicatedResolver} from "../../src/common/DedicatedResolver.sol";
import {IDedicatedResolver, NODE_ANY} from "../../src/common/IDedicatedResolver.sol";
import {IRegistryTraversal} from "../../src/common/IRegistryTraversal.sol";
import {IExtendedResolver} from "@ens/contracts/resolvers/profiles/IExtendedResolver.sol";
import {IUniversalResolver} from "@ens/contracts/universalResolver/IUniversalResolver.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";
import {UUPSProxy} from "@ensdomains/verifiable-factory/UUPSProxy.sol";
import {INameResolver} from "@ens/contracts/resolvers/profiles/INameResolver.sol";
import {IAddrResolver} from "@ens/contracts/resolvers/profiles/IAddrResolver.sol";
import {IAddressResolver} from "@ens/contracts/resolvers/profiles/IAddressResolver.sol";
import {ITextResolver} from "@ens/contracts/resolvers/profiles/ITextResolver.sol";
import {IContentHashResolver} from "@ens/contracts/resolvers/profiles/IContentHashResolver.sol";
import {IPubkeyResolver} from "@ens/contracts/resolvers/profiles/IPubkeyResolver.sol";
import {IABIResolver} from "@ens/contracts/resolvers/profiles/IABIResolver.sol";
import {IInterfaceResolver} from "@ens/contracts/resolvers/profiles/IInterfaceResolver.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {COIN_TYPE_ETH, EVM_BIT} from "@ens/contracts/utils/ENSIP19.sol";

contract DedicatedResolverTest is Test, IRegistryTraversal {
    address foundResolver;
    uint256 foundOffset;

    function findResolver(bytes memory) external view returns (address, bytes32, uint256) {
        return (foundResolver, 0, foundOffset);
    }

    VerifiableFactory factory;
    DedicatedResolver resolverImpl;

    address alice;
    DedicatedResolver aliceResolver;

    string testName = "test.eth";
    bytes testAddress = abi.encodePacked(address(0x123));

    function setUp() external {
        factory = new VerifiableFactory();
        resolverImpl = new DedicatedResolver();

        alice = makeAddr("alice");
        aliceResolver = _deployResolver(alice, true, address(0));
    }

    function _deployResolver(address owner, bool wildcard, address ur) internal returns (DedicatedResolver resolver) {
        bytes memory initData = abi.encodeCall(DedicatedResolver.initialize, (owner, wildcard, ur));
        vm.startPrank(owner);
        resolver = DedicatedResolver(factory.deployProxy(address(resolverImpl), uint256(keccak256(initData)), initData));
        vm.stopPrank();
    }

    function testFuzz_deploy(bool wildcard) external {
        DedicatedResolver resolver = _deployResolver(alice, wildcard, address(1));
        assertEq(resolver.owner(), alice, "owner");
        assertEq(resolver.wildcard(), wildcard, "wildcard");
        assertEq(resolver.universalResolver(), address(1), "ur");
    }

    function testFuzz_supportsInterface() external view {
        assertTrue(aliceResolver.supportsInterface(type(IExtendedResolver).interfaceId), "IExtendedResolver");
        assertTrue(aliceResolver.supportsInterface(type(IDedicatedResolver).interfaceId), "IDedicatedResolver");
        assertTrue(aliceResolver.supportsInterface(DedicatedResolver.multicall.selector), "multicall()");
        assertTrue(ERC165Checker.supportsERC165(address(aliceResolver)), "ERC165");
    }

    function test_supportsName_wildcard() external view {
        assertTrue(aliceResolver.supportsName(""));
        assertTrue(aliceResolver.supportsName(hex"FF"));
    }

    function test_supportsName_noWildcard_noUR() external {
        DedicatedResolver resolver = _deployResolver(alice, false, address(0));
        assertFalse(resolver.supportsName(""));
    }

    function test_supportsName_noWildcard_exact() external {
        DedicatedResolver resolver = _deployResolver(alice, false, address(this));
        foundResolver = address(resolver);
        foundOffset = 0;
        assertTrue(resolver.supportsName(""));
    }

    function test_supportsName_noWildcard_notExact() external {
        DedicatedResolver resolver = _deployResolver(alice, false, address(this));
        foundOffset = 1;
        assertFalse(resolver.supportsName(""));
    }

    function testFuzz_setAddr(uint256 coinType, bytes memory addressBytes) external {
        vm.startPrank(alice);
        aliceResolver.setAddr(coinType, addressBytes);
        vm.stopPrank();

        assertEq(aliceResolver.addr(NODE_ANY, coinType), addressBytes, "immediate");
        bytes memory result = aliceResolver.resolve("", abi.encodeCall(IAddressResolver.addr, (NODE_ANY, coinType)));
        assertEq(abi.decode(result, (bytes)), addressBytes, "extended");
    }

    function test_setAddr_fallback(uint32 chain) external {
        vm.assume(chain < EVM_BIT);
        vm.startPrank(alice);
        aliceResolver.setAddr(EVM_BIT, testAddress);
        vm.stopPrank();
        assertEq(aliceResolver.addr(NODE_ANY, chain == 1 ? COIN_TYPE_ETH : EVM_BIT | chain), testAddress);
    }

    function test_setAddr_notOwner() external {
        vm.expectRevert();
        aliceResolver.setAddr(0, "");
    }

    function testFuzz_setText(string memory key, string memory value) external {
        vm.startPrank(alice);
        aliceResolver.setText(key, value);
        vm.stopPrank();

        assertEq(aliceResolver.text(NODE_ANY, key), value, "immediate");
        bytes memory result = aliceResolver.resolve("", abi.encodeCall(ITextResolver.text, (NODE_ANY, key)));
        assertEq(abi.decode(result, (string)), value, "extended");
    }

    function test_setText_notOwner() external {
        vm.expectRevert();
        aliceResolver.setText("", "");
    }

    function test_setName(string memory name) external {
        vm.startPrank(alice);
        aliceResolver.setName(name);
        vm.stopPrank();

        assertEq(aliceResolver.name(NODE_ANY), name, "immediate");
        bytes memory result = aliceResolver.resolve("", abi.encodeCall(INameResolver.name, (NODE_ANY)));
        assertEq(abi.decode(result, (string)), name, "extended");
    }

    function test_setName_notOwner() external {
        vm.expectRevert();
        aliceResolver.setName("");
    }

    function testFuzz_setContenthash(bytes memory v) external {
        vm.startPrank(alice);
        aliceResolver.setContenthash(v);
        vm.stopPrank();

        assertEq(aliceResolver.contenthash(NODE_ANY), v, "immediate");
        bytes memory result = aliceResolver.resolve("", abi.encodeCall(IContentHashResolver.contenthash, (NODE_ANY)));
        assertEq(abi.decode(result, (bytes)), v, "extended");
    }

    function test_setContenthash_notOwner() external {
        vm.expectRevert();
        aliceResolver.setContenthash("");
    }

    function testFuzz_setPubkey(bytes32 x, bytes32 y) external {
        vm.startPrank(alice);
        aliceResolver.setPubkey(x, y);
        vm.stopPrank();

        (bytes32 x_, bytes32 y_) = aliceResolver.pubkey(NODE_ANY);
        assertEq(abi.encode(x_, y_), abi.encode(x, y), "immediate");
        bytes memory result = aliceResolver.resolve("", abi.encodeCall(IPubkeyResolver.pubkey, (NODE_ANY)));
        assertEq(result, abi.encode(x, y), "extended");
    }

    function test_setPubkey_notOwner() external {
        vm.expectRevert();
        aliceResolver.setPubkey(0, 0);
    }

    function testFuzz_setABI(uint8 bit, bytes memory data) external {
        uint256 contentType = 1 << bit;

        vm.startPrank(alice);
        aliceResolver.setABI(contentType, data);
        vm.stopPrank();

        uint256 contentTypes = ~uint256(0);
        (uint256 contentType_, bytes memory data_) = aliceResolver.ABI(NODE_ANY, contentTypes);
        bytes memory expect = data.length > 0 ? abi.encode(contentType, data) : abi.encode(0, "");
        assertEq(abi.encode(contentType_, data_), expect, "immediate");
        bytes memory result = aliceResolver.resolve("", abi.encodeCall(IABIResolver.ABI, (NODE_ANY, contentTypes)));
        assertEq(result, expect, "extended");
    }

    function test_setABI_invalidContentType() external {
        vm.startPrank(alice);
        vm.expectRevert();
        aliceResolver.setABI(0, "");
        vm.expectRevert();
        aliceResolver.setABI(3, "");
        vm.stopPrank();
    }

    function test_setABI_notOwner() external {
        vm.expectRevert();
        aliceResolver.setABI(1, "");
    }

    function testFuzz_setInterface(bytes4 iface, address impl) external {
        vm.assume(!resolverImpl.supportsInterface(iface));

        vm.startPrank(alice);
        aliceResolver.setInterface(iface, impl);
        vm.stopPrank();

        assertEq(aliceResolver.interfaceImplementer(NODE_ANY, iface), impl, "immediate");
        bytes memory result =
            aliceResolver.resolve("", abi.encodeCall(IInterfaceResolver.interfaceImplementer, (NODE_ANY, iface)));
        assertEq(abi.decode(result, (address)), impl, "extended");
    }

    function test_interfaceImplementer_overlap() external {
        vm.startPrank(alice);
        aliceResolver.setAddr(COIN_TYPE_ETH, abi.encodePacked(aliceResolver));
        vm.stopPrank();
        assertEq(
            aliceResolver.interfaceImplementer(NODE_ANY, type(IExtendedResolver).interfaceId), address(aliceResolver)
        );
        assertEq(
            aliceResolver.interfaceImplementer(NODE_ANY, type(IDedicatedResolver).interfaceId), address(aliceResolver)
        );
        assertEq(
            aliceResolver.interfaceImplementer(NODE_ANY, DedicatedResolver.multicall.selector), address(aliceResolver)
        );
    }

    function test_setInterface_notOwner() external {
        vm.expectRevert();
        aliceResolver.setInterface(bytes4(0), address(0));
    }

    function test_multicall_setters() external {
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(DedicatedResolver.setName, (testName));
        calls[1] = abi.encodeCall(DedicatedResolver.setAddr, (COIN_TYPE_ETH, testAddress));
        vm.startPrank(alice);
        aliceResolver.multicall(calls);
        vm.stopPrank();

        assertEq(aliceResolver.name(NODE_ANY), testName, "name()");
        assertEq(aliceResolver.addr(NODE_ANY, COIN_TYPE_ETH), testAddress, "addr()");
    }

    function test_multicall_setters_notOwner() external {
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(DedicatedResolver.setName, (testName));
        calls[1] = abi.encodeCall(DedicatedResolver.setAddr, (COIN_TYPE_ETH, testAddress));
        vm.expectRevert();
        aliceResolver.multicall(calls);
    }

    function test_multicall_getters() external {
        vm.startPrank(alice);
        aliceResolver.setName(testName);
        aliceResolver.setAddr(COIN_TYPE_ETH, testAddress);
        vm.stopPrank();

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(INameResolver.name, (NODE_ANY));
        calls[1] = abi.encodeCall(IAddressResolver.addr, (NODE_ANY, COIN_TYPE_ETH));

        bytes[] memory answers = new bytes[](2);
        answers[0] = abi.encode(testName);
        answers[1] = abi.encode(testAddress);

        bytes memory expect = abi.encode(answers);
        assertEq(abi.encode(aliceResolver.multicall(calls)), expect, "immediate");
        bytes memory result = aliceResolver.resolve("", abi.encodeCall(DedicatedResolver.multicall, (calls)));
        assertEq(result, expect, "extended");
    }
}
