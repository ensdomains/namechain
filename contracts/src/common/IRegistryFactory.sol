// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {PermissionedRegistry} from "./PermissionedRegistry.sol";
import {IRegistryDatastore} from "./IRegistryDatastore.sol";

/**
 * @title IRegistryFactory
 * @dev Interface for creating new PermissionedRegistry instances
 */
interface IRegistryFactory {
    /**
     * @dev Creates a new PermissionedRegistry instance
     * @param datastore The datastore to use for the new registry
     * @param ownerAddress The address that will receive the owner roles
     * @param ownerRoles The roles to grant to the owner
     * @return The newly created PermissionedRegistry instance
     */
    function createRegistry(
        IRegistryDatastore datastore,
        address ownerAddress,
        uint256 ownerRoles
    ) external returns (PermissionedRegistry);
} 