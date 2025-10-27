// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {EACBaseRolesLib} from "~src/common/access-control/libraries/EACBaseRolesLib.sol";
import {BaseUriRegistryMetadata} from "~src/common/registry/BaseUriRegistryMetadata.sol";
import {PermissionedRegistry} from "~src/common/registry/PermissionedRegistry.sol";
import {RegistryDatastore} from "~src/common/registry/RegistryDatastore.sol";

/// @dev Reusable testing fixture for a simplified ENSv2 ".eth" deployment.
contract ETHRegistryMixin {
    RegistryDatastore datastore;
    BaseUriRegistryMetadata metadata;
    PermissionedRegistry rootRegistry;
    PermissionedRegistry ethRegistry;

    function _deployETHRegistry() internal {
        datastore = new RegistryDatastore();
        metadata = new BaseUriRegistryMetadata();
        rootRegistry = new PermissionedRegistry(
            datastore,
            metadata,
            address(this),
            EACBaseRolesLib.ALL_ROLES
        );
        ethRegistry = new PermissionedRegistry(
            datastore,
            metadata,
            address(this),
            EACBaseRolesLib.ALL_ROLES
        );
        rootRegistry.register(
            "eth",
            address(this),
            ethRegistry,
            address(0),
            EACBaseRolesLib.ALL_ROLES,
            type(uint64).max
        );
    }
}
