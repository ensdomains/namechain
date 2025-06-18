// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {EjectionController} from "../common/EjectionController.sol";
import {TransferData} from "../common/TransferData.sol";
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

    event RenewalSynced(uint256 tokenId, uint64 newExpiry);

    constructor(IPermissionedRegistry _registry) EjectionController(_registry) {}

    /**
     * @dev Should be called when a name has been ejected from L2.  
     *
     * @param transferData The transfer data for the name being ejected
     */
    function completeEjectionFromL2(
        TransferData memory transferData
    ) public virtual returns (uint256 tokenId) {
        tokenId = registry.register(transferData.label, transferData.owner, IRegistry(transferData.subregistry), transferData.resolver, transferData.roleBitmap, transferData.expires);
    }

    /**
     * @dev Sync the renewal of a name with the L2 registry.
     *
     * @param tokenId The token ID of the name
     * @param newExpiry The new expiration timestamp
     */
    function syncRenewal(uint256 tokenId, uint64 newExpiry) external virtual {
        registry.renew(tokenId, newExpiry);
        emit RenewalSynced(tokenId, newExpiry);
    }

    // Internal functions

    /**
     * Overrides the EjectionController._onEject function.
     */
    function _onEject(uint256[] memory tokenIds, TransferData[] memory transferDataArray) internal override virtual {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            TransferData memory transferData = transferDataArray[i];

            // check that the label matches the token id
            _assertTokenIdMatchesLabel(tokenId, transferData.label);

            registry.relinquish(tokenId);
        }
    }
}
