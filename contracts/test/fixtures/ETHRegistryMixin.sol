// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {LibEACBaseRoles} from "../../src/common/EnhancedAccessControl.sol";
import {RegistryDatastore} from "../../src/common/RegistryDatastore.sol";
import {BaseUriRegistryMetadata} from "../../src/common/BaseUriRegistryMetadata.sol";
import {PermissionedRegistry} from "../../src/common/PermissionedRegistry.sol";

contract ETHRegistryMixin {
    RegistryDatastore datastore;
    BaseUriRegistryMetadata metadata;
    PermissionedRegistry rootRegistry;
    PermissionedRegistry ethRegistry;

    function deployETHRegistry() public {
        datastore = new RegistryDatastore();
        metadata = new BaseUriRegistryMetadata();
        rootRegistry = new PermissionedRegistry(
            datastore,
            metadata,
            address(this),
            LibEACBaseRoles.ALL_ROLES
        );
        ethRegistry = new PermissionedRegistry(
            datastore,
            metadata,
            address(this),
            LibEACBaseRoles.ALL_ROLES
        );
        rootRegistry.register(
            "eth",
            address(this),
            ethRegistry,
            address(0),
            LibEACBaseRoles.ALL_ROLES,
            type(uint64).max
        );
    }
}
