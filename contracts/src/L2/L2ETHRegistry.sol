// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IL2EjectionController} from "./IL2EjectionController.sol";
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
 * @title L2ETHRegistry
 * @dev L2 contract for .eth that holds .eth names.
 */
contract L2ETHRegistry is PermissionedRegistry, EjectionControllerMixin {
    error NameNotExpired(uint256 tokenId, uint64 expires);

    event NameEjected(uint256 indexed tokenId, address owner, uint64 expires);
    event NameMigratedToL2(uint256 indexed tokenId, address sendTo);

    IL2EjectionController public ejectionController;

    constructor(IRegistryDatastore _datastore, IL2EjectionController _ejectionController, IRegistryMetadata _registryMetadata) PermissionedRegistry(_datastore, _registryMetadata, ALL_ROLES) {
        _setEjectionController(_ejectionController);
    }

    /**
     * @dev Set a new ejection controller
     * @param _newEjectionController The address of the new controller
     */
    function setEjectionController(IL2EjectionController _newEjectionController) external onlyRoles(ROOT_RESOURCE, ROLE_SET_EJECTION_CONTROLLER) {
        address oldController = address(ejectionController);
        _setEjectionController(_newEjectionController);
        emit EjectionControllerChanged(oldController, address(_newEjectionController));
    }

    /**
     * @dev Eject a name to L1.
     * @param tokenId The token ID of the name
     * @param l1Owner The new owner of the name on L1
     * @param l1Subregistry The new subregistry to use for the name on L1
     */
    function eject(uint256 tokenId, address l1Owner, address l1Subregistry)
        public
        onlyTokenOwner(tokenId)
    {
        setTokenObserver(tokenId, ejectionController);
        _safeTransferFrom(msg.sender, address(ejectionController), tokenId, 1, "");
        IL2EjectionController(ejectionController).ejectToL1(tokenId, l1Owner, l1Subregistry);
    }

    // Internal functions

    function _setEjectionController(IL2EjectionController _newEjectionController) internal {
        if (address(_newEjectionController) == address(0)) {
            revert InvalidEjectionController();
        }
        ejectionController = _newEjectionController;
    }    
}
