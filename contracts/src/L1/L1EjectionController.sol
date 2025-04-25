// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {EjectionController} from "../common/EjectionController.sol";
import {IRegistry} from "../common/IRegistry.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {RegistryRolesMixin} from "../common/RegistryRolesMixin.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";

/**
 * @title L1EjectionController
 * @dev L1 contract for ejection controller that facilitates migrations of names
 * between L1 and L2, as well as handling renewals.
 */
abstract contract L1EjectionController is EjectionController, RegistryRolesMixin {
    error NotTokenOwner(uint256 tokenId);
    error NameNotExpired(uint256 tokenId, uint64 expires);

    constructor(IPermissionedRegistry _registry) EjectionController(_registry) {}

    /**
     * @dev Should be called when a name has been ejected from L2.  
     *
     * @param label The label of the name being ejected
     * @param l1Owner The address that will own the name on L1
     * @param l1Subregistry The subregistry address to use on L1
     * @param l1Resolver The resolver address to use on L1
     */
    function _completeEjectionFromL2(
        string memory label,
        address l1Owner,
        address l1Subregistry,
        address l1Resolver,
        uint64 expires
    ) internal virtual {
        registry.register(label, l1Owner, IRegistry(l1Subregistry), l1Resolver, ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY, expires);
    }

    /**
     * @dev Sync the renewal of a name with the L2 registry.
     *
     * @param tokenId The token ID of the name
     * @param newExpiry The new expiration timestamp
     */
    function _syncRenewal(uint256 tokenId, uint64 newExpiry) internal virtual {
        registry.renew(tokenId, newExpiry);
    }

    // Internal functions

    /**
     * Overrides the EjectionController._onEject function.
     */
    function _onEject(uint256 tokenId, TransferData memory /*transferData*/) internal override virtual {
        if (registry.ownerOf(tokenId) != address(this)) {
            revert NotTokenOwner(tokenId);
        }

        registry.relinquish(tokenId);
    }
}
