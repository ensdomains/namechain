// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IL1EjectionController} from "./IL1EjectionController.sol";
import {ERC1155Singleton} from "../common/ERC1155Singleton.sol";
import {IERC1155Singleton} from "../common/IERC1155Singleton.sol";
import {IRegistry} from "../common/IRegistry.sol";
import {IRegistryDatastore} from "../common/IRegistryDatastore.sol";
import {BaseRegistry} from "../common/BaseRegistry.sol";
import {IRegistryMetadata} from "../common/IRegistryMetadata.sol";
import {IStandardRegistry} from "../common/IStandardRegistry.sol";
import {RegistryRolesMixin} from "../common/RegistryRolesMixin.sol";
import {PermissionedRegistry} from "../common/PermissionedRegistry.sol";
import {EjectionControllerMixin} from "../common/EjectionControllerMixin.sol";


/**
 * @title L1ETHRegistry
 * @dev L1 contract for .eth that holds ejected .eth names only.
 * Unlike the L2 ETHRegistry, this registry does not handle new registrations directly,
 * but receives names that have been ejected from L2.
 */
contract L1ETHRegistry is PermissionedRegistry, EjectionControllerMixin {
    error NameNotExpired(uint256 tokenId, uint64 expires);

    event NameEjected(uint256 indexed tokenId, address owner, uint64 expires);
    event NameMigratedToL2(uint256 indexed tokenId, address sendTo);

    IL1EjectionController public ejectionController;

    modifier onlyEjectionController() {
        if (msg.sender != address(ejectionController)) {
            revert OnlyEjectionController();
        }
        _;
    }

    constructor(IRegistryDatastore _datastore, IL1EjectionController _ejectionController, IRegistryMetadata _registryMetadata) PermissionedRegistry(_datastore, _registryMetadata, ALL_ROLES) {
        _setEjectionController(_ejectionController);
    }

    /**
     * @dev Set a new ejection controller
     * @param _newEjectionController The address of the new controller
     */
    function setEjectionController(IL1EjectionController _newEjectionController) external onlyRoles(ROOT_RESOURCE, ROLE_SET_EJECTION_CONTROLLER) {
        address oldController = address(ejectionController);
        _setEjectionController(_newEjectionController);
        emit EjectionControllerChanged(oldController, address(_newEjectionController));
    }

    /**
     * @dev Receive an ejected name from Namechain.
     * @param tokenId The token ID of the name
     * @param owner The owner of the name
     * @param registry The registry to use for the name
     * @param expires Expiration timestamp
     * @return tokenId The token ID of the ejected name
     */
    function ejectFromNamechain(uint256 tokenId, address owner, IRegistry registry, uint64 expires)
        public
        onlyEjectionController
        returns (uint256)
    {
        // Check if the name is active (not expired)
        (, uint64 oldExpires, uint32 tokenIdVersion) = datastore.getSubregistry(tokenId);
        if (oldExpires >= block.timestamp) {
            revert NameNotExpired(tokenId, oldExpires);
        }

        // Get the actual owner without checking expiration
        address actualOwner = ERC1155Singleton.ownerOf(tokenId);
        if (actualOwner != address(0)) {
            // Burn the token from the actual owner
            _burn(actualOwner, tokenId, 1);
        }

        _mint(owner, tokenId, 1, "");

        datastore.setSubregistry(tokenId, address(registry), expires, tokenIdVersion);

        emit NameEjected(tokenId, owner, expires);
        return tokenId;
    }

    /**
     * @dev Update expiration date for a name. This can only be called by the ejection controller
     * when it receives a notification from L2 about a renewal.
     *
     * @param tokenId The token ID of the name to update
     * @param expires New expiration timestamp
     */
    function updateExpiration(uint256 tokenId, uint64 expires) 
        public 
        onlyEjectionController
    {
        (address subregistry, uint64 oldExpiration, uint32 tokenIdVersion) = datastore.getSubregistry(tokenId);
        
        if (oldExpiration < block.timestamp) {
            revert NameExpired(tokenId);
        }
        
        if (expires < oldExpiration) {
            revert CannotReduceExpiration(oldExpiration, expires);
        }
        
        datastore.setSubregistry(tokenId, subregistry, expires, tokenIdVersion);
        
        emit NameRenewed(tokenId, expires, msg.sender);
    }

    /**
     * @dev Migrate a name back to Namechain, preserving ownership on Namechain.
     * According to section 4.5.6 of the design doc, this process requires
     * the ejection controller to facilitate cross-chain communication.
     * @param tokenId The token ID of the name to migrate
     * @param l2Owner The address to send the name to on L2
     * @param l2Subregistry The subregistry to use on L2 (optional)
     * @param data Extra data
     */
    function migrateToNamechain(uint256 tokenId, address l2Owner, address l2Subregistry, bytes memory data) external onlyTokenOwner(tokenId) {
        address owner = ownerOf(tokenId);
        _burn(owner, tokenId, 1);
        datastore.setSubregistry(tokenId, address(0), 0, 0);

        // Notify the ejection controller to handle cross-chain messaging
        IL1EjectionController(ejectionController).migrateToNamechain(tokenId, l2Owner, l2Subregistry, data);

        emit NameMigratedToL2(tokenId, l2Owner);
    }


    // Internal functions

    function _setEjectionController(IL1EjectionController _newEjectionController) internal {
        if (address(_newEjectionController) == address(0)) {
            revert InvalidEjectionController();
        }
        ejectionController = _newEjectionController;
    }

}