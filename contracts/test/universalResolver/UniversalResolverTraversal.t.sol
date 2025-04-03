// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";
import {UniversalResolver, NameCoder} from "../../src/universalResolver/UniversalResolver.sol";
import {RootRegistry, IRegistry, IRegistryMetadata, IRegistryDatastore} from "../../src/registry/RootRegistry.sol";
import {UserRegistry} from "../../src/registry/UserRegistry.sol";
import {RegistryDatastore} from "../../src/registry/RegistryDatastore.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

contract MockRegistry is UserRegistry {
    constructor(
        IRegistry _parent,
        string memory _label,
        IRegistryDatastore _datastore
    )
        UserRegistry(_parent, _label, _datastore, IRegistryMetadata(address(0)))
    {}
    function setResolver(uint256 tokenId, address resolver) external {
        datastore.setResolver(tokenId, resolver, 0);
    }
}

contract UniversalResolverTraversal is Test, ERC1155Holder {
    RegistryDatastore datastore;
    RootRegistry rootRegistry;
    UniversalResolver ur;

    function setUp() public {
        datastore = new RegistryDatastore();
        rootRegistry = new RootRegistry(datastore);
        rootRegistry.grantRole(rootRegistry.TLD_ISSUER_ROLE(), address(this));
        ur = new UniversalResolver(rootRegistry, new string[](0));
    }

    function _createRegistry(
        IRegistry parent,
        string memory label
    ) internal returns (MockRegistry) {
        return new MockRegistry(parent, label, datastore);
    }

    function test_findResolver_eth() external {
        MockRegistry ethRegistry = _createRegistry(rootRegistry, "eth");
        uint256 tokenId = rootRegistry.mint(
            ethRegistry.label(),
            address(this),
            ethRegistry,
            0,
            ""
        );

        rootRegistry.setResolver(tokenId, address(1));

        bytes memory name = NameCoder.encode(ethRegistry.label());
        (address resolver, , uint256 offset) = ur.findResolver(name);
        (IRegistry registry, bool exact) = ur.getRegistry(name);

        assertEq(resolver, address(1), "resolver");
        assertEq(offset, 0, "offset");
        assertEq(address(registry), address(rootRegistry), "registry");
        assertEq(exact, true, "exact");
    }

    function test_findResolver_resolverOnParent() external {
        MockRegistry ethRegistry = _createRegistry(rootRegistry, "eth");
        MockRegistry raffyRegistry = _createRegistry(ethRegistry, "raffy");
        rootRegistry.mint(
            ethRegistry.label(),
            address(this),
            ethRegistry,
            0,
            ""
        );
        uint256 tokenId = ethRegistry.mint(
            raffyRegistry.label(),
            address(this),
            raffyRegistry,
            0
        );

        ethRegistry.setResolver(tokenId, address(1));

        bytes memory name = NameCoder.encode(
            string.concat(raffyRegistry.label(), ".", ethRegistry.label())
        );
        (address resolver, , uint256 offset) = ur.findResolver(name);
        (IRegistry registry, bool exact) = ur.getRegistry(name);

        assertEq(resolver, address(1), "resolver");
        assertEq(offset, 0, "offset");
        assertEq(address(registry), address(ethRegistry), "registry");
        assertEq(exact, true, "exact");
    }

    function test_findResolver_resolverOnRoot() external {
        MockRegistry ethRegistry = _createRegistry(rootRegistry, "eth");
        MockRegistry raffyRegistry = _createRegistry(ethRegistry, "raffy");
        uint256 tokenId = rootRegistry.mint(
            ethRegistry.label(),
            address(this),
            ethRegistry,
            0,
            ""
        );
        ethRegistry.mint(
            raffyRegistry.label(),
            address(this),
            raffyRegistry,
            0
        );

        rootRegistry.setResolver(tokenId, address(1));

        bytes memory name = NameCoder.encode(
            string.concat(
                "sub.",
                raffyRegistry.label(),
                ".",
                ethRegistry.label()
            )
        );
        (address resolver, , uint256 offset) = ur.findResolver(name);
        (IRegistry registry, bool exact) = ur.getRegistry(name);

        assertEq(resolver, address(1), "resolver");
        assertEq(offset, 10, "offset");
        assertEq(address(registry), address(raffyRegistry), "registry");
        assertEq(exact, true, "exact");
    }

    function test_findResolver_nonExact() external {
        MockRegistry ethRegistry = _createRegistry(rootRegistry, "eth");
        MockRegistry raffyRegistry = _createRegistry(ethRegistry, "raffy");
        uint256 tokenId = rootRegistry.mint(
            ethRegistry.label(),
            address(this),
            ethRegistry,
            0,
            ""
        );
        ethRegistry.mint(
            raffyRegistry.label(),
            address(this),
            raffyRegistry,
            0
        );

        rootRegistry.setResolver(tokenId, address(1));

        bytes memory name = NameCoder.encode(
            string.concat(
                "a.b.",
                raffyRegistry.label(),
                ".",
                ethRegistry.label()
            )
        );
        (address resolver, , uint256 offset) = ur.findResolver(name);
        (IRegistry registry, bool exact) = ur.getRegistry(name);

        assertEq(resolver, address(1), "resolver");
        assertEq(offset, 10, "offset");
        assertEq(address(registry), address(raffyRegistry), "registry");
        assertEq(exact, false, "exact");
    }
}
