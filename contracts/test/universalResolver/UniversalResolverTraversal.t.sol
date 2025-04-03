// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";
import {UniversalResolver} from "../../src/universalResolver/UniversalResolver.sol";
import {RootRegistry, IRegistry, IRegistryMetadata} from "../../src/registry/RootRegistry.sol";
import {UserRegistry} from "../../src/registry/UserRegistry.sol";
import {RegistryDatastore} from "../../src/registry/RegistryDatastore.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

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

    function test_findResolver() external {
        UserRegistry userRegistry = new UserRegistry(
            rootRegistry,
            "eth",
            datastore,
            IRegistryMetadata(address(0))
        );
        uint256 tokenId = rootRegistry.mint(
            userRegistry.label(),
            address(this),
            userRegistry,
            0,
            ""
        );
        rootRegistry.setResolver(tokenId, address(1));

        bytes memory name = NameCoder.encode(userRegistry.label());
        (address resolver, , uint256 offset) = ur.findResolver(name);
        (IRegistry registry, bool exact) = ur.getRegistry(name);

        assertEq(resolver, address(1), "resolver");
        assertEq(offset, 0, "offset");
        assertEq(address(registry), address(rootRegistry), "registry");
        assertEq(exact, true, "exact");
    }
}
