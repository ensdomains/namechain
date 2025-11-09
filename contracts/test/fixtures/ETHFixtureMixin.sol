// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {EACBaseRolesLib} from "~src/common/access-control/libraries/EACBaseRolesLib.sol";
import {BaseUriRegistryMetadata} from "~src/common/registry/BaseUriRegistryMetadata.sol";
import {PermissionedRegistry} from "~src/common/registry/PermissionedRegistry.sol";
import {RegistryDatastore} from "~src/common/registry/RegistryDatastore.sol";

/// @dev Reusable testing fixture for a simplified ENSv2 ".eth" deployment.
contract ETHFixtureMixin {
    struct ETHFixture {
        RegistryDatastore datastore;
        BaseUriRegistryMetadata metadata;
        PermissionedRegistry rootRegistry;
        PermissionedRegistry ethRegistry;
    }

    function deployETHFixture() internal returns (ETHFixture memory f) {
        f.datastore = new RegistryDatastore();
        f.metadata = new BaseUriRegistryMetadata();
        f.rootRegistry = new PermissionedRegistry(
            f.datastore,
            f.metadata,
            address(this),
            EACBaseRolesLib.ALL_ROLES
        );
        f.ethRegistry = new PermissionedRegistry(
            f.datastore,
            f.metadata,
            address(this),
            EACBaseRolesLib.ALL_ROLES
        );
        f.rootRegistry.register(
            "eth",
            address(this),
            f.ethRegistry,
            address(0),
            EACBaseRolesLib.ALL_ROLES,
            type(uint64).max
        );
    }
}
