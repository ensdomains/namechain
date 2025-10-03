// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {LibEACBaseRoles} from "../../src/common/EnhancedAccessControl.sol";
import {RegistryDatastore} from "../../src/common/RegistryDatastore.sol";
import {BaseUriRegistryMetadata} from "../../src/common/BaseUriRegistryMetadata.sol";
import {PermissionedRegistry} from "../../src/common/PermissionedRegistry.sol";

contract ETHRegistryMixin {
    RegistryDatastore datastore;
    BaseUriRegistryMetadata metadata;
    PermissionedRegistry ethRegistry;

    function deployEthRegistry() public {
        datastore = new RegistryDatastore();
        metadata = new BaseUriRegistryMetadata();
        ethRegistry = new PermissionedRegistry(
            datastore,
            metadata,
            address(this),
            LibEACBaseRoles.ALL_ROLES
        );
    }
}
