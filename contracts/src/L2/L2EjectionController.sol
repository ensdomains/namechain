// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ITokenObserver} from "../common/ITokenObserver.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {PermissionedRegistry} from "../common/PermissionedRegistry.sol";
import {EjectionController, TransferData} from "../common/EjectionController.sol";
import {NameUtils} from "../common/NameUtils.sol";
import {IRegistry} from "../common/IRegistry.sol";  
import {RegistryRolesMixin} from "../common/RegistryRolesMixin.sol";

/**
 * @title L2EjectionController
 * @dev L2 contract for ejection controller that facilitates migrations of names
 * between L1 and L2, as well as handling renewals.
 */
abstract contract L2EjectionController is EjectionController, ITokenObserver, RegistryRolesMixin {
    error NotTokenOwner(uint256 tokenId);
    error InvalidLabel(uint256 tokenId, string label);
    error UnauthorizedEjection(uint256 tokenId, address owner);

    constructor(IPermissionedRegistry _registry) EjectionController(_registry) {}

    /**
     * @dev Should be called when a name is being migrated back to L2.
     *
     * @param tokenId The token ID of the name being migrated
     * @param transferData The transfer data for the name being migrated
     */
    function _completeMigrationFromL1(
        uint256 tokenId,
        TransferData memory transferData
    ) internal virtual {
        if (registry.ownerOf(tokenId) != address(this)) {
            revert NotTokenOwner(tokenId);
        }

        registry.setSubregistry(tokenId, IRegistry(transferData.subregistry));
        registry.setResolver(tokenId, transferData.resolver);
        registry.safeTransferFrom(address(this), transferData.owner, tokenId, 1, "");
    }

    function supportsInterface(bytes4 interfaceId) public view override(EjectionController) returns (bool) {
        return interfaceId == type(ITokenObserver).interfaceId || super.supportsInterface(interfaceId);
    }

    // Internal functions

    /**
     * Overrides the EjectionController._onEject function.
     */
    function _onEject(uint256[] memory tokenIds, TransferData[] memory transferDataArray) internal virtual override {
        uint256 tokenId;
        TransferData memory transferData;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            tokenId = tokenIds[i];
            transferData = transferDataArray[i];

            // check that the label matches the token id
            if (NameUtils.labelToCanonicalId(transferData.label) != NameUtils.getCanonicalId(tokenId)) {
                revert InvalidLabel(tokenId, transferData.label);
            }

            // Check if the controller (current owner after transfer) has the ROLE_CAN_EJECT role
            bytes32 tokenResource = bytes32(NameUtils.getCanonicalId(tokenId));
            if (!PermissionedRegistry(address(registry)).hasRoles(tokenResource, ROLE_CAN_EJECT, address(this))) {
                revert UnauthorizedEjection(tokenId, address(this));
            }

            registry.setSubregistry(tokenId, IRegistry(address(0)));

            // listen for events
            registry.setTokenObserver(tokenId, this);
        }
    }
}
