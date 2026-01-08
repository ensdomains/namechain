// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {EACBaseRolesLib} from "~src/common/access-control/EnhancedAccessControl.sol";
import {
    PermissionedRegistry,
    IRegistryMetadata
} from "~src/common/registry/PermissionedRegistry.sol";
import {RegistryFinder, IRegistry} from "~src/universalResolver/RegistryFinder.sol";
import {RegistryDatastore} from "~src/common/registry/RegistryDatastore.sol";

contract RegistryFinderTest is Test, ERC1155Holder {
    RegistryDatastore datastore;
    address resolverAddress = makeAddr("resolver");

    function _createRegistry() internal returns (PermissionedRegistry) {
        return
            new PermissionedRegistry(
                datastore,
                IRegistryMetadata(address(0)),
                address(this),
                EACBaseRolesLib.ALL_ROLES
            );
    }

    function setUp() external {
        datastore = new RegistryDatastore();
    }

    function test_findRegistries_eth() external {
        vm.pauseGasMetering();
        PermissionedRegistry ethRegistry = _createRegistry();
        RegistryFinder finder = new RegistryFinder(ethRegistry, NameCoder.encode("eth"));
        vm.resumeGasMetering();

        IRegistry[] memory registries = finder.findRegistries(NameCoder.encode("eth"));

        assertEq(registries.length, 2, "length");
        assertEq(address(registries[0]), address(ethRegistry), "0");
        assertEq(address(registries[1]), address(0), "1");
    }

    function test_findRegistries_test_eth() external {
        vm.pauseGasMetering();
        PermissionedRegistry ethRegistry = _createRegistry();
        PermissionedRegistry testRegistry = _createRegistry();
        RegistryFinder finder = new RegistryFinder(ethRegistry, NameCoder.encode("eth"));
        ethRegistry.register(
            "test",
            address(this),
            testRegistry,
            resolverAddress,
            EACBaseRolesLib.ALL_ROLES,
            uint64(block.timestamp + 1000)
        );
        vm.resumeGasMetering();

        IRegistry[] memory registries = finder.findRegistries(NameCoder.encode("test.eth"));

        assertEq(registries.length, 3, "length");
        assertEq(address(registries[0]), address(testRegistry), "0");
        assertEq(address(registries[1]), address(ethRegistry), "1");
        assertEq(address(registries[2]), address(0), "2");
    }

    function test_findRegistries_sub_test_eth() external {
        vm.pauseGasMetering();
        PermissionedRegistry ethRegistry = _createRegistry();
        PermissionedRegistry testRegistry = _createRegistry();
        RegistryFinder finder = new RegistryFinder(ethRegistry, NameCoder.encode("eth"));
        ethRegistry.register(
            "test",
            address(this),
            testRegistry,
            address(0),
            EACBaseRolesLib.ALL_ROLES,
            uint64(block.timestamp + 1000)
        );
        testRegistry.register(
            "test",
            address(this),
            IRegistry(address(0)),
            resolverAddress,
            EACBaseRolesLib.ALL_ROLES,
            uint64(block.timestamp + 1000)
        );
        vm.resumeGasMetering();

        IRegistry[] memory registries = finder.findRegistries(NameCoder.encode("sub.test.eth"));

        assertEq(registries.length, 4, "length");
        assertEq(address(registries[0]), address(0), "0");
        assertEq(address(registries[1]), address(testRegistry), "1");
        assertEq(address(registries[2]), address(ethRegistry), "2");
        assertEq(address(registries[3]), address(0), "3");
    }
}
