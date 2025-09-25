// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IRegistryDatastore} from "../common/registry/interfaces/IRegistryDatastore.sol";
import {IRegistryMetadata} from "../common/registry/interfaces/IRegistryMetadata.sol";
import {PermissionedRegistry} from "../common/registry/PermissionedRegistry.sol";
import {SimpleRegistryMetadata} from "../common/registry/SimpleRegistryMetadata.sol";
/**
 * @title UserRegistry
 * @dev A user registry that inherits from PermissionedRegistry and is upgradeable using the UUPS pattern.
 * This contract is designed to be deployed via the VerifiableFactory.
 */
contract UserRegistry is Initializable, PermissionedRegistry, UUPSUpgradeable {
    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    uint256 internal constant _ROLE_UPGRADE = 1 << 20;

    uint256 internal constant _ROLE_UPGRADE_ADMIN = _ROLE_UPGRADE << 128;

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor()
        PermissionedRegistry(
            IRegistryDatastore(address(0)),
            IRegistryMetadata(address(0)),
            _msgSender(),
            0
        )
    {
        // This disables initialization for the implementation contract
        _disableInitializers();
    }

    /**
     * @dev Initializes the UserRegistry contract.
     * @param datastore_ The registry datastore contract.
     * @param metadata_ The registry metadata contract.
     * @param deployerRoles_ The roles to grant to the deployer.
     * @param admin_ The address that will be set as the admin with upgrade privileges.
     */
    function initialize(
        IRegistryDatastore datastore_,
        IRegistryMetadata metadata_,
        uint256 deployerRoles_,
        address admin_
    ) public initializer {
        // TODO: require => custom error
        require(admin_ != address(0), "Admin cannot be zero address");

        // Initialize datastore
        datastore = datastore_;

        // Initialize metadata provider
        if (address(metadata_) == address(0)) {
            // Create a new SimpleRegistryMetadata if none is provided
            _updateMetadataProvider(new SimpleRegistryMetadata());
        } else {
            metadataProvider = metadata_;
        }

        // Grant deployer roles to the admin
        _grantRoles(ROOT_RESOURCE, deployerRoles_, admin_, false);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(UUPSUpgradeable).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @inheritdoc UUPSUpgradeable
    ///
    /// @dev Only accounts with the ROLE_UPGRADE_ADMIN role can upgrade the contract.
    ///
    /// @param newImplementation The address of the new implementation.
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRootRoles(_ROLE_UPGRADE) {
        // Authorization is handled by the onlyRootRoles modifier
    }
}
