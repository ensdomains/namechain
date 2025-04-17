// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {PermissionedRegistry} from "./PermissionedRegistry.sol";
import {IRegistryDatastore} from "./IRegistryDatastore.sol";
import {IRegistryMetadata} from "./IRegistryMetadata.sol";

abstract contract ETHRegistry is PermissionedRegistry {
    error InvalidEjectionController();
    error OnlyEjectionController();

    event EjectionControllerChanged(address oldController, address newController);

    address public ejectionController;

    modifier onlyEjectionController() {
        if (msg.sender != ejectionController) {
            revert OnlyEjectionController();
        }
        _;
    }

    constructor(IRegistryDatastore _datastore, IRegistryMetadata _registryMetadata, address _ejectionController) PermissionedRegistry(_datastore, _registryMetadata, ALL_ROLES) {
        _setEjectionController(_ejectionController);
    }

    /**
     * @dev Set a new ejection controller
     * @param _newEjectionController The address of the new controller
     */
    function setEjectionController(address _newEjectionController) external onlyRoles(ROOT_RESOURCE, ROLE_SET_EJECTION_CONTROLLER) {
        _setEjectionController(_newEjectionController);
    }

    // Internal functions

    function _setEjectionController(address _newEjectionController) internal {
        address oldController = ejectionController;

        if (address(_newEjectionController) == address(0)) {
            revert InvalidEjectionController();
        }
        ejectionController = _newEjectionController;

        emit EjectionControllerChanged(oldController, _newEjectionController);
    }
}
