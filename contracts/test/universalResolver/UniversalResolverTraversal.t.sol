// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";
import {UniversalResolver, NameCoder} from "../../src/universalResolver/UniversalResolver.sol";
import {IRegistry} from "../../src/common/IRegistry.sol";
import {PermissionedRegistry} from "../../src/common/PermissionedRegistry.sol";
import {RegistryDatastore} from "../../src/common/RegistryDatastore.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IRegistryDatastore} from "../../src/common/IRegistryDatastore.sol";
import {IRegistryMetadata} from "../../src/common/IRegistryMetadata.sol";

contract MockRegistry is PermissionedRegistry {
    constructor(
        IRegistryDatastore _datastore
    )
        PermissionedRegistry(_datastore, IRegistryMetadata(address(0)), ALL_ROLES)
    {}
}

contract UniversalResolverTraversal is Test, ERC1155Holder {
    uint256 constant public ALL_ROLES = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    RegistryDatastore datastore;
    PermissionedRegistry rootRegistry;
    UniversalResolver universalResolver;

    function setUp() public {
        datastore = new RegistryDatastore();
        rootRegistry = new PermissionedRegistry(datastore, IRegistryMetadata(address(0)), ALL_ROLES);
        universalResolver = new UniversalResolver(
            rootRegistry,
            new string[](0)
        );
    }

    function test_findResolver_eth() external {
        //     name:  eth
        // registry: <eth> <root>
        // resolver:  0x1
        MockRegistry ethRegistry = new MockRegistry(
            datastore
        );
        uint256 tokenId = rootRegistry.register(
            "eth",
            address(this),
            ethRegistry,
            address(0),
            ALL_ROLES,
            uint64(block.timestamp + 1000)
        );

        rootRegistry.setResolver(tokenId, address(1));

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
        //     name:  raffy . eth
        // registry: <raffy> <eth> <root>
        // resolver:   0x1
        MockRegistry ethRegistry = new MockRegistry(
            datastore
        );
        MockRegistry raffyRegistry = new MockRegistry(
            datastore
        );
        rootRegistry.register(
            "eth",
            address(this),
            ethRegistry,
            address(0),
            ALL_ROLES,
            uint64(block.timestamp + 1000)
        );
        uint256 tokenId = ethRegistry.register(
            "raffy",
            address(this),
            raffyRegistry,
            address(0),
            ALL_ROLES,
            uint64(block.timestamp + 1000)
        );

        ethRegistry.setResolver(tokenId, address(1));

        bytes memory name = NameCoder.encode(
            string.concat("raffy", ".", "eth")
        );
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
        assertEq(label, "raffy", "label");
        assertEq(address(registry), address(raffyRegistry), "registry");
        assertEq(exact, true, "exact");
    }

    function test_findResolver_resolverOnRoot() external {
        //     name:  sub . raffy . eth
        // registry:       <raffy> <eth> <root>
        // resolver:                0x1
        MockRegistry ethRegistry = new MockRegistry(
            datastore
        );
        MockRegistry raffyRegistry = new MockRegistry(
            datastore
        );
        uint256 tokenId = rootRegistry.register(
            "eth",
            address(this),
            ethRegistry,
            address(0),
            ALL_ROLES,
            uint64(block.timestamp + 1000)
        );
        ethRegistry.register(
            "raffy",
            address(this),
            raffyRegistry,
            address(0),
            ALL_ROLES,
            uint64(block.timestamp + 1000)
        );

        rootRegistry.setResolver(tokenId, address(1));

        string memory sub = "sub";
        bytes memory name = NameCoder.encode(
            string.concat(
                sub,
                ".",
                "raffy",
                ".",
                "eth"
            )
        );
        (address resolver, , uint256 offset) = universalResolver.findResolver(
            name
        );
        (IRegistry parentRegistry, string memory label) = universalResolver
            .getParentRegistry(name);
        (IRegistry registry, bool exact) = universalResolver.getRegistry(name);

        assertEq(resolver, address(1), "resolver");
        assertEq(offset, 10, "offset");
        assertEq(
            address(parentRegistry),
            address(raffyRegistry),
            "parentRegistry"
        );
        assertEq(label, sub, "label");
        assertEq(address(registry), address(raffyRegistry), "registry");
        assertEq(exact, false, "exact");
    }

    function test_findResolver_virtual() external {
        //     name:  a . b . raffy . eth
        // registry:         <raffy> <eth> <root>
        // resolver:                  0x1
        MockRegistry ethRegistry = new MockRegistry(
            datastore
        );
        MockRegistry raffyRegistry = new MockRegistry(
            datastore
        );
        uint256 tokenId = rootRegistry.register(
            "eth",
            address(this),
            ethRegistry,
            address(0),
            ALL_ROLES,
            uint64(block.timestamp + 1000)
        );
        ethRegistry.register(
            "raffy",
            address(this),
            raffyRegistry,
            address(0),
            ALL_ROLES,
            uint64(block.timestamp + 1000)
        );

        rootRegistry.setResolver(tokenId, address(1));

        bytes memory name = NameCoder.encode(
            string.concat(
                "a.b.",
                "raffy",
                ".",
                "eth"
            )
        );
        (address resolver, , uint256 offset) = universalResolver.findResolver(
            name
        );
        (IRegistry parentRegistry, string memory label) = universalResolver
            .getParentRegistry(name);
        (IRegistry registry, bool exact) = universalResolver.getRegistry(name);

        assertEq(resolver, address(1), "resolver");
        assertEq(offset, 10, "offset");
        assertEq(address(parentRegistry), address(0), "parentRegistry");
        assertEq(label, "", "label");
        assertEq(address(registry), address(raffyRegistry), "registry");
        assertEq(exact, false, "exact");
    }
}
