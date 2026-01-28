// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

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
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {ENSIP19, COIN_TYPE_ETH, COIN_TYPE_DEFAULT} from "@ens/contracts/utils/ENSIP19.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {IEnhancedAccessControl} from "~src/access-control/interfaces/IEnhancedAccessControl.sol";
import {EACBaseRolesLib} from "~src/access-control/libraries/EACBaseRolesLib.sol";
import {OwnedResolver, OwnedResolverLib} from "~src/resolver/OwnedResolver.sol";
import {MockHCAFactoryBasic} from "~test/mocks/MockHCAFactoryBasic.sol";

contract OwnedResolverTest is Test {
    uint256 constant DEFAULT_ROLES = EACBaseRolesLib.ALL_ROLES;
    uint256 constant ROOT_RESOURCE = 0;

    struct I {
        bytes4 interfaceId;
        string name;
    }
    function _supportedInterfaces() internal pure returns (I[] memory v) {
        uint256 i;
        v = new I[](13);
        v[i++] = I(type(IExtendedResolver).interfaceId, "IExtendedResolver");
        v[i++] = I(type(IMulticallable).interfaceId, "IMulticallable");
        v[i++] = I(type(IABIResolver).interfaceId, "IABIResolver");
        v[i++] = I(type(IAddrResolver).interfaceId, "IAddrResolver");
        v[i++] = I(type(IAddressResolver).interfaceId, "IAddressResolver");
        v[i++] = I(type(IContentHashResolver).interfaceId, "IContentHashResolver");
        v[i++] = I(type(IHasAddressResolver).interfaceId, "IHasAddressResolver");
        v[i++] = I(type(IInterfaceResolver).interfaceId, "IInterfaceResolver");
        v[i++] = I(type(INameResolver).interfaceId, "INameResolver");
        v[i++] = I(type(IPubkeyResolver).interfaceId, "IPubkeyResolver");
        v[i++] = I(type(ITextResolver).interfaceId, "ITextResolver");
        v[i++] = I(type(UUPSUpgradeable).interfaceId, "UUPSUpgradeable");
        v[i++] = I(type(IEnhancedAccessControl).interfaceId, "IEnhancedAccessControl");
        assertEq(v.length, i);
    }

    MockHCAFactoryBasic hcaFactory;
    OwnedResolver resolver;

    address owner = makeAddr("owner");
    address friend = makeAddr("friend");

    bytes testName;
    address testAddr = 0x8000000000000000000000000000000000000001;
    bytes testAddress = abi.encodePacked(testAddr);

    function setUp() external {
        VerifiableFactory factory = new VerifiableFactory();
        hcaFactory = new MockHCAFactoryBasic();
        OwnedResolver resolverImpl = new OwnedResolver(hcaFactory);
        testName = NameCoder.encode("test.eth");

        bytes memory initData = abi.encodeCall(OwnedResolver.initialize, (owner, DEFAULT_ROLES));
        resolver = OwnedResolver(
            factory.deployProxy(address(resolverImpl), uint256(keccak256(initData)), initData)
        );
    }

    function test_initialize() external view {
        assertTrue(resolver.hasRootRoles(DEFAULT_ROLES, owner));
    }

    function test_upgrade() external {
        MockUpgrade upgrade = new MockUpgrade();
        vm.prank(owner);
        resolver.upgradeToAndCall(address(upgrade), "");
        assertEq(
            resolver.addr(NameCoder.namehash(testName, 0)),
            upgrade.addr(NameCoder.namehash(testName, 0))
        );
    }

    function test_upgrade_noRole() external {
        MockUpgrade upgrade = new MockUpgrade();
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                ROOT_RESOURCE,
                OwnedResolverLib.ROLE_UPGRADE,
                friend
            )
        );
        vm.prank(friend);
        resolver.upgradeToAndCall(address(upgrade), "");
    }

    function test_supportsInterface() external view {
        assertTrue(ERC165Checker.supportsERC165(address(resolver)), "ERC165");
        I[] memory v = _supportedInterfaces();
        for (uint256 i; i < v.length; i++) {
            assertTrue(
                ERC165Checker.supportsInterface(address(resolver), v[i].interfaceId),
                v[i].name
            );
        }
    }

    function test_alias_none() external view {
        assertEq(resolver.getAlias(NameCoder.encode("test.eth")), "", "test");
        assertEq(resolver.getAlias(NameCoder.encode("")), "", "root");
        assertEq(resolver.getAlias(NameCoder.encode("xyz")), "", "xyz");
    }

    function test_alias_root() external {
        resolver.setAlias(NameCoder.encode(""), NameCoder.encode("test.eth"));

        assertEq(resolver.getAlias(NameCoder.encode("")), NameCoder.encode("test.eth"), "root");
        assertEq(
            resolver.getAlias(NameCoder.encode("sub")),
            NameCoder.encode("sub.test.eth"),
            "sub"
        );
    }

    function test_alias_exact() external {
        resolver.setAlias(NameCoder.encode("other.eth"), NameCoder.encode("test.eth"));

        assertEq(
            resolver.getAlias(NameCoder.encode("other.eth")),
            NameCoder.encode("test.eth"),
            "exact"
        );
    }

    function test_alias_subdomain() external {
        resolver.setAlias(NameCoder.encode("com"), NameCoder.encode("eth"));

        assertEq(resolver.getAlias(NameCoder.encode("com")), NameCoder.encode("eth"), "exact");
        assertEq(
            resolver.getAlias(NameCoder.encode("test.com")),
            NameCoder.encode("test.eth"),
            "alias"
        );
    }

    function test_alias_recursive() external {
        resolver.setAlias(NameCoder.encode("ens.xyz"), NameCoder.encode("com"));
        resolver.setAlias(NameCoder.encode("com"), NameCoder.encode("eth"));

        assertEq(
            resolver.getAlias(NameCoder.encode("test.ens.xyz")),
            NameCoder.encode("test.eth"),
            "alias"
        );
    }

    function test_setAddr(uint256 coinType, bytes memory addressBytes) external {
        if (ENSIP19.isEVMCoinType(coinType)) {
            addressBytes = vm.randomBool() ? vm.randomBytes(20) : new bytes(0);
        }
        vm.prank(owner);
        resolver.setAddr(NameCoder.namehash(testName, 0), coinType, addressBytes);

        assertEq(resolver.addr(NameCoder.namehash(testName, 0), coinType), addressBytes);
    }

    function test_setAddr_fallback(uint32 chain) external {
        vm.assume(chain < COIN_TYPE_DEFAULT);
        bytes memory a = vm.randomBytes(20);

        vm.prank(owner);
        resolver.setAddr(NameCoder.namehash(testName, 0), COIN_TYPE_DEFAULT, a);

        assertEq(
            resolver.addr(
                NameCoder.namehash(testName, 0),
                chain == 1 ? COIN_TYPE_ETH : COIN_TYPE_DEFAULT | chain
            ),
            a
        );
    }

    function test_setAddr_zeroEVM() external {
        vm.prank(owner);
        resolver.setAddr(
            NameCoder.namehash(testName, 0),
            COIN_TYPE_ETH,
            abi.encodePacked(address(0))
        );

        assertTrue(resolver.hasAddr(NameCoder.namehash(testName, 0), COIN_TYPE_ETH), "null");
        assertFalse(resolver.hasAddr(NameCoder.namehash(testName, 0), COIN_TYPE_DEFAULT), "unset");
    }

    function test_setAddr_zeroEVM_fallbacks() external {
        vm.startPrank(owner);
        resolver.setAddr(
            NameCoder.namehash(testName, 0),
            COIN_TYPE_DEFAULT,
            abi.encodePacked(address(1))
        );
        resolver.setAddr(
            NameCoder.namehash(testName, 0),
            COIN_TYPE_DEFAULT | 1,
            abi.encodePacked(address(0))
        );
        resolver.setAddr(
            NameCoder.namehash(testName, 0),
            COIN_TYPE_DEFAULT | 2,
            abi.encodePacked(address(2))
        );
        vm.stopPrank();

        assertEq(
            resolver.addr(NameCoder.namehash(testName, 0), COIN_TYPE_DEFAULT | 1),
            abi.encodePacked(address(0)),
            "block"
        );
        assertEq(
            resolver.addr(NameCoder.namehash(testName, 0), COIN_TYPE_DEFAULT | 2),
            abi.encodePacked(address(2)),
            "override"
        );
        assertEq(
            resolver.addr(NameCoder.namehash(testName, 0), COIN_TYPE_DEFAULT | 3),
            abi.encodePacked(address(1)),
            "fallback"
        );
    }

    function test_setAddr_invalidEVM_tooShort() external {
        bytes memory v = new bytes(1);
        vm.expectRevert(abi.encodeWithSelector(OwnedResolver.InvalidEVMAddress.selector, v));
        vm.prank(owner);
        resolver.setAddr(NameCoder.namehash(testName, 0), COIN_TYPE_ETH, v);
    }

    function test_setAddr_invalidEVM_tooLong() external {
        bytes memory v = new bytes(21);
        vm.expectRevert(abi.encodeWithSelector(OwnedResolver.InvalidEVMAddress.selector, v));
        vm.prank(owner);
        resolver.setAddr(NameCoder.namehash(testName, 0), COIN_TYPE_ETH, v);
    }

    function test_setAddr_notAuthorized() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                OwnedResolverLib.nodeResource(NameCoder.namehash(testName, 0)),
                OwnedResolverLib.ROLE_SET_ADDR,
                address(this)
            )
        );
        resolver.setAddr(NameCoder.namehash(testName, 0), COIN_TYPE_ETH, "");
    }
}

contract MockUpgrade is UUPSUpgradeable {
    function addr(bytes32) external pure returns (address) {
        return address(1);
    }
    function _authorizeUpgrade(address) internal override {}
}
