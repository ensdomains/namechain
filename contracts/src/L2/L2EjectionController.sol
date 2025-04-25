// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {EjectionController} from "../common/EjectionController.sol";
import {NameUtils} from "../common/NameUtils.sol";
import {IRegistry} from "../common/IRegistry.sol";  

/**
 * @title L2EjectionController
 * @dev L2 contract for ejection controller that facilitates migrations of names
 * between L1 and L2, as well as handling renewals.
 */
abstract contract L2EjectionController is EjectionController {
    error NotTokenOwner(uint256 tokenId);
    error InvalidLabel(uint256 tokenId, string label);

    constructor(IPermissionedRegistry _registry) EjectionController(_registry) {}

    /**
     * @dev Should be called when a name is being migrated back to L2.
     *
     * @param tokenId The token ID of the name being migrated
     * @param l2Owner The address that will own the name on L2
     * @param l2Subregistry The subregistry address to use on L2
     * @param l2Resolver The resolver address to use on L2
     */
    function _completeMigrationFromL1(
        uint256 tokenId,
        address l2Owner,
        address l2Subregistry,
        address l2Resolver
    ) internal virtual {
        if (registry.ownerOf(tokenId) != address(this)) {
            revert NotTokenOwner(tokenId);
        }

        registry.setSubregistry(tokenId, IRegistry(l2Subregistry));
        registry.setResolver(tokenId, l2Resolver);
        registry.safeTransferFrom(address(this), l2Owner, tokenId, 1, "");
    }

    // Internal functions

    /**
     * Overrides the EjectionController._onEject function.
     */
    function _onEject(uint256 tokenId, TransferData memory transferData) internal virtual override {
        if (registry.ownerOf(tokenId) != address(this)) {
            revert NotTokenOwner(tokenId);
        }

        // check that the label matches the token id
        if (NameUtils.labelToCanonicalId(transferData.label) != NameUtils.getCanonicalId(tokenId)) {
            revert InvalidLabel(tokenId, transferData.label);
        }

        registry.setSubregistry(tokenId, IRegistry(address(0)));

        // listen for events
        registry.setTokenObserver(tokenId, this);
    }
}
