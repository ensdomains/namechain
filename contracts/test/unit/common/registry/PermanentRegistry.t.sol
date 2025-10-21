// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";

import {EACBaseRolesLib} from "~src/common/access-control/EnhancedAccessControl.sol";
import {
    IEnhancedAccessControl
} from "~src/common/access-control/interfaces/IEnhancedAccessControl.sol";
import {IRegistry} from "~src/common/registry/interfaces/IRegistry.sol";
import {IPermanentRegistry} from "~src/common/registry/interfaces/IPermanentRegistry.sol";
import {PermanentRegistry} from "~src/common/registry/PermanentRegistry.sol";
import {RegistryDatastore} from "~src/common/registry/RegistryDatastore.sol";
import {RegistryRolesLib} from "~src/common/registry/libraries/RegistryRolesLib.sol";
import {BaseUriRegistryMetadata} from "~src/common/registry/BaseUriRegistryMetadata.sol";

contract PermanentRegistryTest is Test {
    RegistryDatastore datastore;
    BaseUriRegistryMetadata metadata;

    PermanentRegistry registry;

    address owner = makeAddr("owner");
    address user = makeAddr("user");
    address user2 = makeAddr("user2");

    function setUp() external {
        datastore = new RegistryDatastore();
        metadata = new BaseUriRegistryMetadata();
        registry = new PermanentRegistry(owner, EACBaseRolesLib.ALL_ROLES, datastore, metadata);
    }

    function test_constructor() external view {
        assertEq(address(registry.DATASTORE()), address(datastore), "DATASTORE");
        assertEq(address(registry.METADATA_PROVIDER()), address(metadata), "METADATA_PROVIDER");
        assertTrue(registry.hasRoles(0, EACBaseRolesLib.ALL_ROLES, owner));
    }

    function test_supportsInterface() external view {
        assertTrue(registry.supportsInterface(type(IPermanentRegistry).interfaceId));
    }

    function test_register() external {
        string memory label = "test";
        IRegistry subregistry = IRegistry(address(1));
        address resolver = address(2);
        uint256 rolesBitmap = RegistryRolesLib.ROLE_SET_RESOLVER |
            RegistryRolesLib.ROLE_SET_SUBREGISTRY;
        vm.prank(owner);
        uint256 id = registry.register(label, user, subregistry, resolver, rolesBitmap, true);
        assertTrue(registry.hasRoles(id, rolesBitmap, user), "roles");
        assertEq(address(registry.getSubregistry(label)), address(subregistry), "subregistry");
        assertEq(registry.getResolver(label), resolver, "resolver");
    }

    function test_register_withoutReset() external {
        string memory label = "test";
        uint256 rolesBitmap = RegistryRolesLib.ROLE_SET_RESOLVER;
        vm.prank(owner);
        uint256 id = registry.register(
            label,
            user,
            IRegistry(address(0)),
            address(0),
            rolesBitmap,
            true
        );
        vm.prank(owner);
        uint256 id2 = registry.register(
            label,
            user2,
            IRegistry(address(0)),
            address(0),
            rolesBitmap,
            false
        );
        assertEq(id, id2, "id");
        assertTrue(registry.hasRoles(id, rolesBitmap, user), "user");
        assertTrue(registry.hasRoles(id, rolesBitmap, user2), "user2");
    }

    function test_Revert_register_noRoles() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                0,
                RegistryRolesLib.ROLE_REGISTRAR,
                address(this)
            )
        );
        registry.register("test", user, IRegistry(address(0)), address(0), 0, true);
    }

    function test_setSubregistry() external {
        string memory label = "test";
        vm.prank(owner);
        registry.register(
            label,
            user,
            IRegistry(address(0)),
            address(0),
            RegistryRolesLib.ROLE_SET_SUBREGISTRY,
            true
        );
        assertEq(address(registry.getSubregistry(label)), address(0), "before");
        vm.prank(user);
        registry.setSubregistry(label, IRegistry(address(1)));
        assertEq(address(registry.getSubregistry(label)), address(1), "after");
    }

    function test_Revert_setSubregistry_noRoles() external {
        string memory label = "test";
        vm.prank(owner);
        uint256 id = registry.register(
            label,
            user,
            IRegistry(address(0)),
            address(0),
            RegistryRolesLib.ROLE_SET_SUBREGISTRY,
            true
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                id,
                RegistryRolesLib.ROLE_SET_SUBREGISTRY,
                address(this)
            )
        );
        registry.setSubregistry(label, IRegistry(address(1)));
    }

    function test_setResolver() external {
        string memory label = "test";
        vm.prank(owner);
        registry.register(
            label,
            user,
            IRegistry(address(0)),
            address(0),
            RegistryRolesLib.ROLE_SET_RESOLVER,
            true
        );
        assertEq(registry.getResolver(label), address(0), "before");
        vm.prank(user);
        registry.setResolver(label, address(1));
        assertEq(registry.getResolver(label), address(1), "after");
    }

    function test_Revert_setResolver_noRoles() external {
        string memory label = "test";
        vm.prank(owner);
        uint256 id = registry.register(
            label,
            user,
            IRegistry(address(0)),
            address(0),
            RegistryRolesLib.ROLE_SET_RESOLVER,
            true
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                id,
                RegistryRolesLib.ROLE_SET_RESOLVER,
                address(this)
            )
        );
        registry.setResolver(label, address(1));
    }
}
