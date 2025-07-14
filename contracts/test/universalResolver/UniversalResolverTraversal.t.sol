// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {UniversalResolver, NameCoder} from "../../src/universalResolver/UniversalResolver.sol";
import {PermissionedRegistry, IRegistry, IRegistryMetadata} from "../../src/common/PermissionedRegistry.sol";
import {RegistryDatastore} from "../../src/common/RegistryDatastore.sol";
import {LibEACBaseRoles} from "../../src/common/EnhancedAccessControl.sol";

contract UniversalResolverTraversal is Test, ERC1155Holder {
    RegistryDatastore datastore;
    PermissionedRegistry rootRegistry;
    UniversalResolver universalResolver;

    function _createRegistry() internal returns (PermissionedRegistry) {
        return
            new PermissionedRegistry(
                datastore,
                IRegistryMetadata(address(0)),
                address(this),
                LibEACBaseRoles.ALL_ROLES
            );
    }

    function setUp() public {
        datastore = new RegistryDatastore();
        rootRegistry = _createRegistry();
        universalResolver = new UniversalResolver(
            rootRegistry,
            new string[](0)
        );
    }

    function test_findResolver_eth() external {
        //     name:  eth
        // registry: <eth> <root>
        // resolver:  0x1
        PermissionedRegistry ethRegistry = _createRegistry();
        rootRegistry.register(
            "eth",
            address(this),
            ethRegistry,
            address(1),
            LibEACBaseRoles.ALL_ROLES,
            uint64(block.timestamp + 1000)
        );

        bytes memory name = NameCoder.encode("eth");
        (address resolver, , uint256 offset) = universalResolver.findResolver(
            name
        );
        (IRegistry parentRegistry, string memory label) = universalResolver
            .getParentRegistry(name);
        (IRegistry registry, bool exact) = universalResolver.getRegistry(name);

        assertEq(resolver, address(1), "resolver");
        assertEq(offset, 0, "offset");
        assertEq(
            address(parentRegistry),
            address(rootRegistry),
            "parentRegistry"
        );
        assertEq(label, "eth", "label");
        assertEq(address(registry), address(ethRegistry), "registry");
        assertEq(exact, true, "exact");
    }

    function test_findResolver_resolverOnParent() external {
        //     name:  test . eth
        // registry: <test> <eth> <root>
        // resolver:   0x1
        PermissionedRegistry ethRegistry = _createRegistry();
        PermissionedRegistry testRegistry = _createRegistry();
        rootRegistry.register(
            "eth",
            address(this),
            ethRegistry,
            address(0),
            LibEACBaseRoles.ALL_ROLES,
            uint64(block.timestamp + 1000)
        );
        ethRegistry.register(
            "test",
            address(this),
            testRegistry,
            address(1),
            LibEACBaseRoles.ALL_ROLES,
            uint64(block.timestamp + 1000)
        );

        bytes memory name = NameCoder.encode("test.eth");
        (address resolver, , uint256 offset) = universalResolver.findResolver(
            name
        );
        (IRegistry parentRegistry, string memory label) = universalResolver
            .getParentRegistry(name);
        (IRegistry registry, bool exact) = universalResolver.getRegistry(name);

        assertEq(resolver, address(1), "resolver");
        assertEq(offset, 0, "offset");
        assertEq(
            address(parentRegistry),
            address(ethRegistry),
            "parentRegistry"
        );
        assertEq(label, "test", "label");
        assertEq(address(registry), address(testRegistry), "registry");
        assertEq(exact, true, "exact");
    }

    function test_findResolver_resolverOnRoot() external {
        //     name:  sub . test . eth
        // registry:       <test> <eth> <root>
        // resolver:               0x1
        PermissionedRegistry ethRegistry = _createRegistry();
        PermissionedRegistry testRegistry = _createRegistry();
        rootRegistry.register(
            "eth",
            address(this),
            ethRegistry,
            address(1),
            LibEACBaseRoles.ALL_ROLES,
            uint64(block.timestamp + 1000)
        );
        ethRegistry.register(
            "test",
            address(this),
            testRegistry,
            address(0),
            LibEACBaseRoles.ALL_ROLES,
            uint64(block.timestamp + 1000)
        );

        bytes memory name = NameCoder.encode("sub.test.eth");
        (address resolver, , uint256 offset) = universalResolver.findResolver(
            name
        );
        (IRegistry parentRegistry, string memory label) = universalResolver
            .getParentRegistry(name);
        (IRegistry registry, bool exact) = universalResolver.getRegistry(name);

        assertEq(resolver, address(1), "resolver");
        assertEq(offset, 9, "offset");
        assertEq(
            address(parentRegistry),
            address(testRegistry),
            "parentRegistry"
        );
        assertEq(label, "sub", "label");
        assertEq(address(registry), address(testRegistry), "registry");
        assertEq(exact, false, "exact");
    }

    function test_findResolver_virtual() external {
        //     name:  a . b . test . eth
        // registry:         <test> <eth> <root>
        // resolver:                 0x1
        PermissionedRegistry ethRegistry = _createRegistry();
        PermissionedRegistry testRegistry = _createRegistry();
        rootRegistry.register(
            "eth",
            address(this),
            ethRegistry,
            address(1),
            LibEACBaseRoles.ALL_ROLES,
            uint64(block.timestamp + 1000)
        );
        ethRegistry.register(
            "test",
            address(this),
            testRegistry,
            address(0),
            LibEACBaseRoles.ALL_ROLES,
            uint64(block.timestamp + 1000)
        );

        bytes memory name = NameCoder.encode("a.b.test.eth");
        (address resolver, , uint256 offset) = universalResolver.findResolver(
            name
        );
        (IRegistry parentRegistry, string memory label) = universalResolver
            .getParentRegistry(name);
        (IRegistry registry, bool exact) = universalResolver.getRegistry(name);

        assertEq(resolver, address(1), "resolver");
        assertEq(offset, 9, "offset");
        assertEq(address(parentRegistry), address(0), "parentRegistry");
        assertEq(label, "", "label");
        assertEq(address(registry), address(testRegistry), "registry");
        assertEq(exact, false, "exact");
    }
}
