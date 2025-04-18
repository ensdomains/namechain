// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {PermissionedRegistry} from "./PermissionedRegistry.sol";
import {IRegistryDatastore} from "./IRegistryDatastore.sol";
import {IRegistryMetadata} from "./IRegistryMetadata.sol";
import {ITokenObserver} from "./ITokenObserver.sol";
import {IEjectionController} from "./IEjectionController.sol";
import {IRegistry} from "./IRegistry.sol";

abstract contract ETHRegistry is PermissionedRegistry, ITokenObserver {
    error InvalidEjectionController();
    error OnlyEjectionController();

    event EjectionControllerChanged(address oldController, address newController);

    IEjectionController public ejectionController;

    modifier onlyEjectionController() {
        if (msg.sender != address(ejectionController)) {
            revert OnlyEjectionController();
        }
        _;
    }

    constructor(IRegistryDatastore _datastore, IRegistryMetadata _registryMetadata, IEjectionController _ejectionController) PermissionedRegistry(_datastore, _registryMetadata, ALL_ROLES) {
        _setEjectionController(_ejectionController);
    }

    /**
     * @dev Set a new ejection controller
     * @param _newEjectionController The address of the new controller
     */
    function setEjectionController(IEjectionController _newEjectionController) external onlyRoles(ROOT_RESOURCE, ROLE_SET_EJECTION_CONTROLLER) {
        _setEjectionController(_newEjectionController);
    }

    /**
     * Implements ITokenObserver.onRenew
     */
    function onRenew(uint256 tokenId, uint64 expires, address renewedBy) external {
        if (address(ejectionController) != address(0)) {
            ejectionController.onRenew(tokenId, expires, renewedBy);
        }
    }

    /**
     * Implements ITokenObserver.onRelinquish
     */
    function onRelinquish(uint256 tokenId, address relinquishedBy) external {
        if (address(ejectionController) != address(0)) {
            ejectionController.onRelinquish(tokenId, relinquishedBy);
        }
    }

    // Internal functions

    function _generateTokenId(uint256 tokenId, address registry, uint64 expires, uint32 tokenIdVersion) internal virtual override returns (uint256 newTokenId) {
        newTokenId = super._generateTokenId(tokenId, registry, expires, tokenIdVersion);
        tokenObservers[tokenId] = this;
    }

    function _setEjectionController(IEjectionController _newEjectionController) internal virtual {
        address oldController = address(ejectionController);

        if (address(_newEjectionController) == address(0)) {
            revert InvalidEjectionController();
        }
        
        ejectionController = _newEjectionController;

        emit EjectionControllerChanged(oldController, address(_newEjectionController));
    }
}
