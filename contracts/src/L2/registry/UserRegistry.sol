// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IRegistryDatastore} from "../../common/registry/interfaces/IRegistryDatastore.sol";
import {IRegistryMetadata} from "../../common/registry/interfaces/IRegistryMetadata.sol";
import {RegistryRolesLib} from "../../common/registry/libraries/RegistryRolesLib.sol";
import {PermissionedRegistry} from "../../common/registry/PermissionedRegistry.sol";

/**
 * @title UserRegistry
 * @dev A user registry that inherits from PermissionedRegistry and is upgradeable using the UUPS pattern.
 * This contract is designed to be deployed via the VerifiableFactory.
 */
contract UserRegistry is Initializable, PermissionedRegistry, UUPSUpgradeable {
    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(
        IRegistryDatastore datastore_,
        IRegistryMetadata metadataProvider_
    ) PermissionedRegistry(datastore_, metadataProvider_, _msgSender(), 0) {
        // This disables initialization for the implementation contract
        _disableInitializers();
    }

    /**
     * @dev Initializes the UserRegistry contract.
     * @param deployerRoles_ The roles to grant to the deployer.
     * @param admin_ The address that will be set as the admin with upgrade privileges.
     */
    function initialize(uint256 deployerRoles_, address admin_) public initializer {
        // TODO: custom error
        require(admin_ != address(0), "Admin cannot be zero address");

        // Datastore and metadata provider are set immutably in constructor

        // Grant deployer roles to the admin
        _grantRoles(ROOT_RESOURCE, deployerRoles_, admin_, false);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(UUPSUpgradeable).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    /**
     * @dev Function that authorizes an upgrade to a new implementation.
     *      Only accounts with the _ROLE_UPGRADE_ADMIN role can upgrade the contract.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRootRoles(RegistryRolesLib.ROLE_UPGRADE) {
        // Authorization is handled by the onlyRootRoles modifier
    }
}
