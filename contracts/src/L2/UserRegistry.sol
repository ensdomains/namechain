// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SimpleRegistryMetadata} from "../common/SimpleRegistryMetadata.sol";
import {PermissionedRegistry} from "../common/PermissionedRegistry.sol";
import {IRegistryDatastore} from "../common/IRegistryDatastore.sol";
import {IRegistryMetadata} from "../common/IRegistryMetadata.sol";
import {IRegistry} from "../common/IRegistry.sol";

/**
 * @title UserRegistry
 * @dev A user registry that inherits from PermissionedRegistry and is upgradeable using the UUPS pattern.
 * This contract is designed to be deployed via the VerifiableFactory.
 */
contract UserRegistry is Initializable, PermissionedRegistry, UUPSUpgradeable {

    constructor() PermissionedRegistry(IRegistryDatastore(address(0)), IRegistryMetadata(address(0)), 0) {
        // This disables initialization for the implementation contract
        _disableInitializers();
    }

    /**
     * @dev Initializes the UserRegistry contract.
     * @param _datastore The registry datastore contract.
     * @param _metadata The registry metadata contract.
     * @param _deployerRoles The roles to grant to the deployer.
     * @param admin The address that will be set as the admin with upgrade privileges.
     */
    function initialize(
        IRegistryDatastore _datastore,
        IRegistryMetadata _metadata,
        uint256 _deployerRoles,
        address admin
    ) public initializer {
        require(admin != address(0), "Admin cannot be zero address");
        
        // Initialize datastore
        datastore = _datastore;
        
        // Initialize metadata provider
        if (address(_metadata) == address(0)) {
            // Create a new SimpleRegistryMetadata if none is provided
            _updateMetadataProvider(new SimpleRegistryMetadata());
        } else {
            metadataProvider = _metadata;
        }
        
        // Grant deployer roles to the admin
        _grantRoles(ROOT_RESOURCE, _deployerRoles, admin, false);
    }

    /**
     * @dev Function that authorizes an upgrade to a new implementation.
     * Only accounts with the ROLE_UPGRADE_ADMIN role can upgrade the contract.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRootRoles(ROLE_UPGRADE_ADMIN) {
        // Authorization is handled by the onlyRootRoles modifier
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(UUPSUpgradeable).interfaceId || super.supportsInterface(interfaceId);
    }
}
