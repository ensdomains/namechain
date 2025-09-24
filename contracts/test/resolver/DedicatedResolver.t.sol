// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, ordering/ordering, one-contract-per-file

import {IMulticallable} from "@ens/contracts/resolvers/IMulticallable.sol";
import {IABIResolver} from "@ens/contracts/resolvers/profiles/IABIResolver.sol";
import {IAddressResolver} from "@ens/contracts/resolvers/profiles/IAddressResolver.sol";
import {IAddrResolver} from "@ens/contracts/resolvers/profiles/IAddrResolver.sol";
import {IContentHashResolver} from "@ens/contracts/resolvers/profiles/IContentHashResolver.sol";
import {IExtendedResolver} from "@ens/contracts/resolvers/profiles/IExtendedResolver.sol";
import {IHasAddressResolver} from "@ens/contracts/resolvers/profiles/IHasAddressResolver.sol";
import {IInterfaceResolver} from "@ens/contracts/resolvers/profiles/IInterfaceResolver.sol";
import {INameResolver} from "@ens/contracts/resolvers/profiles/INameResolver.sol";
import {IPubkeyResolver} from "@ens/contracts/resolvers/profiles/IPubkeyResolver.sol";
import {ITextResolver} from "@ens/contracts/resolvers/profiles/ITextResolver.sol";
import {ResolverFeatures} from "@ens/contracts/resolvers/ResolverFeatures.sol";
import {ENSIP19, COIN_TYPE_ETH, COIN_TYPE_DEFAULT} from "@ens/contracts/utils/ENSIP19.sol";
import {IERC7996} from "@ens/contracts/utils/IERC7996.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {Test} from "forge-std/Test.sol";

import {DedicatedResolver} from "./../../src/common/DedicatedResolver.sol";
import {
    IDedicatedResolverSetters,
    NODE_ANY
} from "./../../src/common/IDedicatedResolverSetters.sol";

contract DedicatedResolverTest is Test {
    struct I {
        bytes4 interfaceId;
        string name;
    }
    function _supportedInterfaces() internal pure returns (I[] memory v) {
        uint256 i;
        v = new I[](13);
        v[i++] = I(type(IExtendedResolver).interfaceId, "IExtendedResolver");
        v[i++] = I(type(IDedicatedResolverSetters).interfaceId, "IDedicatedResolverSetters");
        v[i++] = I(type(IMulticallable).interfaceId, "IMulticallable");
        v[i++] = I(type(IAddrResolver).interfaceId, "IAddrResolver");
        v[i++] = I(type(IAddressResolver).interfaceId, "IAddressResolver");
        v[i++] = I(type(IHasAddressResolver).interfaceId, "IHasAddressResolver");
        v[i++] = I(type(ITextResolver).interfaceId, "ITextResolver");
        v[i++] = I(type(IContentHashResolver).interfaceId, "IContentHashResolver");
        v[i++] = I(type(IPubkeyResolver).interfaceId, "IPubkeyResolver");
        v[i++] = I(type(INameResolver).interfaceId, "INameResolver");
        v[i++] = I(type(IABIResolver).interfaceId, "IABIResolver");
        v[i++] = I(type(IInterfaceResolver).interfaceId, "IInterfaceResolver");
        v[i++] = I(type(IERC7996).interfaceId, "IERC7996");
        assertEq(v.length, i);
    }

    address owner;
    DedicatedResolver resolver;

    string testName = "test.eth";
    bytes testAddress = abi.encodePacked(address(0x123));

    function setUp() external {
        VerifiableFactory factory = new VerifiableFactory();
        DedicatedResolver resolverImpl = new DedicatedResolver();

        owner = makeAddr("owner");
        bytes memory initData = abi.encodeCall(DedicatedResolver.initialize, (owner));
        resolver = DedicatedResolver(
            factory.deployProxy(address(resolverImpl), uint256(keccak256(initData)), initData)
        );
    }

    function test_owner() external view {
        assertEq(resolver.owner(), owner);
    }

    function testFuzz_supportsInterface() external view {
        assertTrue(ERC165Checker.supportsERC165(address(resolver)), "ERC165");
        I[] memory v = _supportedInterfaces();
        for (uint256 i; i < v.length; i++) {
            assertTrue(
                ERC165Checker.supportsInterface(address(resolver), v[i].interfaceId),
                v[i].name
            );
        }
    }

    function test_supportsFeature() external view {
        assertTrue(
            resolver.supportsFeature(ResolverFeatures.RESOLVE_MULTICALL),
            "RESOLVE_MULTICALL"
        );
        assertTrue(resolver.supportsFeature(ResolverFeatures.SINGULAR), "SINGULAR");
    }

    function testFuzz_setAddr(uint256 coinType, bytes memory addressBytes) external {
        if (ENSIP19.isEVMCoinType(coinType)) {
            addressBytes = vm.randomBool() ? vm.randomBytes(20) : new bytes(0);
        }
        vm.startPrank(owner);
        resolver.setAddr(coinType, addressBytes);
        vm.stopPrank();

        assertEq(resolver.addr(NODE_ANY, coinType), addressBytes, "immediate");
        bytes memory result = resolver.resolve(
            "",
            abi.encodeCall(IAddressResolver.addr, (NODE_ANY, coinType))
        );
        assertEq(abi.decode(result, (bytes)), addressBytes, "extended");
    }

    function test_setAddr_fallback(uint32 chain) external {
        vm.assume(chain < COIN_TYPE_DEFAULT);
        bytes memory a = vm.randomBytes(20);

        vm.startPrank(owner);
        resolver.setAddr(COIN_TYPE_DEFAULT, a);
        vm.stopPrank();

        assertEq(
            resolver.addr(NODE_ANY, chain == 1 ? COIN_TYPE_ETH : COIN_TYPE_DEFAULT | chain),
            a
        );
    }

    function test_setAddr_zeroEVM() external {
        vm.startPrank(owner);
        resolver.setAddr(COIN_TYPE_ETH, abi.encodePacked(address(0)));
        vm.stopPrank();

        assertTrue(resolver.hasAddr(NODE_ANY, COIN_TYPE_ETH), "null");
        assertFalse(resolver.hasAddr(NODE_ANY, COIN_TYPE_DEFAULT), "unset");
    }

    function test_setAddr_zeroEVM_fallbacks() external {
        vm.startPrank(owner);
        resolver.setAddr(COIN_TYPE_DEFAULT, abi.encodePacked(address(1)));
        resolver.setAddr(COIN_TYPE_DEFAULT | 1, abi.encodePacked(address(0)));
        resolver.setAddr(COIN_TYPE_DEFAULT | 2, abi.encodePacked(address(2)));
        vm.stopPrank();

        assertEq(
            resolver.addr(NODE_ANY, COIN_TYPE_DEFAULT | 1),
            abi.encodePacked(address(0)),
            "block"
        );
        assertEq(
            resolver.addr(NODE_ANY, COIN_TYPE_DEFAULT | 2),
            abi.encodePacked(address(2)),
            "override"
        );
        assertEq(
            resolver.addr(NODE_ANY, COIN_TYPE_DEFAULT | 3),
            abi.encodePacked(address(1)),
            "fallback"
        );
    }

    function test_setAddr_invalidEVM() external {
        vm.expectRevert();
        resolver.setAddr(COIN_TYPE_ETH, new bytes(1));
        vm.expectRevert();
        resolver.setAddr(COIN_TYPE_DEFAULT, new bytes(21));
    }

    function test_setAddr_notOwner() external {
        vm.expectRevert();
        resolver.setAddr(0, "");
    }

    function testFuzz_setText(string memory key, string memory value) external {
        vm.startPrank(owner);
        resolver.setText(key, value);
        vm.stopPrank();

        assertEq(resolver.text(NODE_ANY, key), value, "immediate");
        bytes memory result = resolver.resolve(
            "",
            abi.encodeCall(ITextResolver.text, (NODE_ANY, key))
        );
        assertEq(abi.decode(result, (string)), value, "extended");
    }

    function test_setText_notOwner() external {
        vm.expectRevert();
        resolver.setText("", "");
    }

    function test_setName(string memory name) external {
        vm.startPrank(owner);
        resolver.setName(name);
        vm.stopPrank();

        assertEq(resolver.name(NODE_ANY), name, "immediate");
        bytes memory result = resolver.resolve("", abi.encodeCall(INameResolver.name, (NODE_ANY)));
        assertEq(abi.decode(result, (string)), name, "extended");
    }

    function test_setName_notOwner() external {
        vm.expectRevert();
        resolver.setName("");
    }

    function testFuzz_setContenthash(bytes memory v) external {
        vm.startPrank(owner);
        resolver.setContenthash(v);
        vm.stopPrank();

        assertEq(resolver.contenthash(NODE_ANY), v, "immediate");
        bytes memory result = resolver.resolve(
            "",
            abi.encodeCall(IContentHashResolver.contenthash, (NODE_ANY))
        );
        assertEq(abi.decode(result, (bytes)), v, "extended");
    }

    function test_setContenthash_notOwner() external {
        vm.expectRevert();
        resolver.setContenthash("");
    }

    function testFuzz_setPubkey(bytes32 x, bytes32 y) external {
        vm.startPrank(owner);
        resolver.setPubkey(x, y);
        vm.stopPrank();

        (bytes32 x_, bytes32 y_) = resolver.pubkey(NODE_ANY);
        assertEq(abi.encode(x_, y_), abi.encode(x, y), "immediate");
        bytes memory result = resolver.resolve(
            "",
            abi.encodeCall(IPubkeyResolver.pubkey, (NODE_ANY))
        );
        assertEq(result, abi.encode(x, y), "extended");
    }

    function test_setPubkey_notOwner() external {
        vm.expectRevert();
        resolver.setPubkey(0, 0);
    }

    function testFuzz_setABI(uint8 bit, bytes memory data) external {
        uint256 contentType = 1 << bit;

        vm.startPrank(owner);
        resolver.setABI(contentType, data);
        vm.stopPrank();

        uint256 contentTypes = ~uint256(0);
        (uint256 contentType_, bytes memory data_) = resolver.ABI(NODE_ANY, contentTypes);
        bytes memory expect = data.length > 0 ? abi.encode(contentType, data) : abi.encode(0, "");
        assertEq(abi.encode(contentType_, data_), expect, "immediate");
        bytes memory result = resolver.resolve(
            "",
            abi.encodeCall(IABIResolver.ABI, (NODE_ANY, contentTypes))
        );
        assertEq(result, expect, "extended");
    }

    function test_setABI_invalidContentType() external {
        vm.startPrank(owner);
        vm.expectRevert();
        resolver.setABI(0, "");
        vm.expectRevert();
        resolver.setABI(3, "");
        vm.stopPrank();
    }

    function test_setABI_notOwner() external {
        vm.expectRevert();
        resolver.setABI(1, "");
    }

    function testFuzz_setInterface(bytes4 interfaceId, address impl) external {
        vm.assume(!resolver.supportsInterface(interfaceId));

        vm.startPrank(owner);
        resolver.setInterface(interfaceId, impl);
        vm.stopPrank();

        assertEq(resolver.interfaceImplementer(NODE_ANY, interfaceId), impl, "immediate");
        bytes memory result = resolver.resolve(
            "",
            abi.encodeCall(IInterfaceResolver.interfaceImplementer, (NODE_ANY, interfaceId))
        );
        assertEq(abi.decode(result, (address)), impl, "extended");
    }

    function test_interfaceImplementer_overlap() external {
        vm.startPrank(owner);
        resolver.setAddr(COIN_TYPE_ETH, abi.encodePacked(resolver));
        vm.stopPrank();

        I[] memory v = _supportedInterfaces();
        for (uint256 i; i < v.length; i++) {
            assertEq(
                resolver.interfaceImplementer(NODE_ANY, v[i].interfaceId),
                address(resolver),
                v[i].name
            );
        }
    }

    function test_setInterface_notOwner() external {
        vm.expectRevert();
        resolver.setInterface(bytes4(0), address(0));
    }

    function test_multicall_setters() external {
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(DedicatedResolver.setName, (testName));
        calls[1] = abi.encodeCall(DedicatedResolver.setAddr, (COIN_TYPE_ETH, testAddress));

        vm.startPrank(owner);
        resolver.multicall(calls);
        vm.stopPrank();

        assertEq(resolver.name(NODE_ANY), testName, "name()");
        assertEq(resolver.addr(NODE_ANY, COIN_TYPE_ETH), testAddress, "addr()");
    }

    function test_multicall_setters_notOwner() external {
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(DedicatedResolver.setName, (testName));
        calls[1] = abi.encodeCall(DedicatedResolver.setAddr, (COIN_TYPE_ETH, testAddress));

        vm.expectRevert();
        resolver.multicall(calls);
    }

    function test_multicall_getters() external {
        vm.startPrank(owner);
        resolver.setName(testName);
        resolver.setAddr(COIN_TYPE_ETH, testAddress);
        vm.stopPrank();

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(INameResolver.name, (NODE_ANY));
        calls[1] = abi.encodeCall(IAddressResolver.addr, (NODE_ANY, COIN_TYPE_ETH));

        bytes[] memory answers = new bytes[](2);
        answers[0] = abi.encode(testName);
        answers[1] = abi.encode(testAddress);

        bytes memory expect = abi.encode(answers);
        assertEq(abi.encode(resolver.multicall(calls)), expect, "immediate");
        bytes memory result = resolver.resolve(
            "",
            abi.encodeCall(DedicatedResolver.multicall, (calls))
        );
        assertEq(result, expect, "extended");
    }
}
