// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering, one-contract-per-file

import {Test} from "forge-std/Test.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {EACBaseRolesLib} from "~src/access-control/EnhancedAccessControl.sol";
import {IHCAFactoryBasic} from "~src/hca/interfaces/IHCAFactoryBasic.sol";
import {
    PermissionedRegistry,
    IRegistryMetadata
} from "~src/registry/PermissionedRegistry.sol";
import {RegistryDatastore} from "~src/registry/RegistryDatastore.sol";
import {LibRegistry, IRegistry, NameCoder} from "~src/universalResolver/libraries/LibRegistry.sol";

contract LibRegistryTest is Test, ERC1155Holder {
    RegistryDatastore datastore;
    PermissionedRegistry rootRegistry;
    address resolverAddress = makeAddr("resolver");

    function _createRegistry() internal returns (PermissionedRegistry) {
        return
            new PermissionedRegistry(
                datastore,
                IHCAFactoryBasic(address(0)),
                IRegistryMetadata(address(0)),
                address(this),
                EACBaseRolesLib.ALL_ROLES
            );
    }
    function _register(
        PermissionedRegistry parentRegistry,
        string memory label,
        IRegistry registry,
        address resolver
    ) internal {
        parentRegistry.register(
            label,
            address(this),
            registry,
            resolver,
            EACBaseRolesLib.ALL_ROLES,
            uint64(block.timestamp + 1000)
        );
    }

    function setUp() external {
        datastore = new RegistryDatastore();
        rootRegistry = _createRegistry();
    }

    function _expectFind(
        bytes memory name,
        uint256 resolverOffset,
        address parentRegistry,
        IRegistry[] memory registries
    ) internal view {
        (IRegistry registry, address resolver, bytes32 node, uint256 resolverOffset_) = LibRegistry
            .findResolver(rootRegistry, name, 0);
        assertEq(
            address(LibRegistry.findExactRegistry(rootRegistry, name, 0)),
            address(registry),
            "exact"
        );
        assertEq(resolver, resolverAddress, "resolver");
        assertEq(node, NameCoder.namehash(name, 0), "node");
        assertEq(resolverOffset_, resolverOffset, "offset");
        assertEq(
            address(LibRegistry.findParentRegistry(rootRegistry, name, 0)),
            parentRegistry,
            "parent"
        );
        IRegistry[] memory regs = LibRegistry.findRegistries(rootRegistry, name, 0);
        assertEq(registries.length, regs.length, "count");
        for (uint256 i; i < regs.length; ++i) {
            assertEq(
                address(registries[i]),
                address(regs[i]),
                string.concat("registry[", vm.toString(i), "]")
            );
        }
        uint256 offset;
        for (uint256 i; i < registries.length; ++i) {
            assertEq(
                address(LibRegistry.findExactRegistry(rootRegistry, name, offset)),
                address(registries[i]),
                string.concat("exact[", vm.toString(i), "]")
            );
            (, offset) = NameCoder.nextLabel(name, offset);
        }
        assertEq(offset, name.length, "length");
        (IRegistry registryFrom, address resolverFrom) = LibRegistry.findResolverFromParent(
            name,
            0,
            name.length - 1,
            rootRegistry,
            address(0)
        );
        assertEq(address(registryFrom), address(registry), "registryFrom");
        assertEq(resolverFrom, resolver, "resolverFrom");
    }

    function test_findResolver_eth() external {
        bytes memory name = NameCoder.encode("eth");
        //     name:  eth
        // registry: <eth> <root>
        // resolver:   X
        vm.pauseGasMetering();
        PermissionedRegistry ethRegistry = _createRegistry();
        rootRegistry.register(
            "eth",
            address(this),
            ethRegistry,
            resolverAddress,
            EACBaseRolesLib.ALL_ROLES,
            uint64(block.timestamp + 1000)
        );
        vm.resumeGasMetering();

        IRegistry[] memory v = new IRegistry[](2);
        v[0] = ethRegistry;
        v[1] = rootRegistry;
        _expectFind(name, 0, address(rootRegistry), v);
    }

    function test_findResolver_resolverOnParent() external {
        bytes memory name = NameCoder.encode("test.eth");
        //     name:  test . eth
        // registry: <test> <eth> <root>
        // resolver:   X
        vm.pauseGasMetering();
        PermissionedRegistry ethRegistry = _createRegistry();
        PermissionedRegistry testRegistry = _createRegistry();
        _register(rootRegistry, "eth", ethRegistry, address(0));
        _register(ethRegistry, "test", testRegistry, resolverAddress);
        vm.resumeGasMetering();

        IRegistry[] memory v = new IRegistry[](3);
        v[0] = testRegistry;
        v[1] = ethRegistry;
        v[2] = rootRegistry;
        _expectFind(name, 0, address(ethRegistry), v);
    }

    function test_findResolver_resolverOnRoot() external {
        bytes memory name = NameCoder.encode("sub.test.eth");
        //     name:  sub . test . eth
        // registry:       <test> <eth> <root>
        // resolver:                X
        vm.pauseGasMetering();
        PermissionedRegistry ethRegistry = _createRegistry();
        PermissionedRegistry testRegistry = _createRegistry();
        _register(rootRegistry, "eth", ethRegistry, resolverAddress);
        _register(ethRegistry, "test", testRegistry, address(0));
        vm.resumeGasMetering();

        IRegistry[] memory v = new IRegistry[](4);
        v[1] = testRegistry;
        v[2] = ethRegistry;
        v[3] = rootRegistry;
        _expectFind(name, 9, address(testRegistry), v); // 3sub4test
    }

    function test_findResolver_virtual() external {
        bytes memory name = NameCoder.encode("a.bb.test.eth");
        //     name:  a . bb . test . eth
        // registry:          <test> <eth> <root>
        // resolver:                   X
        vm.pauseGasMetering();
        PermissionedRegistry ethRegistry = _createRegistry();
        PermissionedRegistry testRegistry = _createRegistry();
        _register(rootRegistry, "eth", ethRegistry, resolverAddress);
        _register(ethRegistry, "test", testRegistry, address(0));
        vm.resumeGasMetering();

        IRegistry[] memory v = new IRegistry[](5);
        v[2] = testRegistry;
        v[3] = ethRegistry;
        v[4] = rootRegistry;
        _expectFind(name, 10, address(0), v); // 1a2bb4test
    }
}
