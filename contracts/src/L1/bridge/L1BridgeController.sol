// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {EjectionController} from "../../common/bridge/EjectionController.sol";
import {IBridge} from "../../common/bridge/interfaces/IBridge.sol";
import {BridgeEncoderLib} from "../../common/bridge/libraries/BridgeEncoderLib.sol";
import {BridgeRolesLib} from "../../common/bridge/libraries/BridgeRolesLib.sol";
import {TransferData} from "../../common/bridge/types/TransferData.sol";
import {IPermissionedRegistry} from "../../common/registry/interfaces/IPermissionedRegistry.sol";
import {IRegistry} from "../../common/registry/interfaces/IRegistry.sol";
import {RegistryRolesLib} from "../../common/registry/libraries/RegistryRolesLib.sol";
import {LibLabel} from "../../common/utils/LibLabel.sol";

/**
 * @title L1BridgeController
 * @dev L1 contract for bridge controller that facilitates migrations of names
 * between L1 and L2, as well as handling renewals.
 */
contract L1BridgeController is EjectionController {
    ////////////////////////////////////////////////////////////////////////
    // Events
    ////////////////////////////////////////////////////////////////////////

    event RenewalSynchronized(uint256 tokenId, uint64 newExpiry);

    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    //error NotTokenOwner(uint256 tokenId);

    error LockedNameCannotBeEjected(uint256 tokenId);

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(
        IPermissionedRegistry registry,
        IBridge bridge
    ) EjectionController(registry, bridge) {}

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    /**
     * @dev Should be called when a name is being ejected to L1.
     *
     * @param td The transfer data for the name being ejected
     */
    function completeEjectionToL1(
        TransferData calldata td
    ) external virtual onlyRootRoles(BridgeRolesLib.ROLE_EJECTOR) returns (uint256 tokenId) {
        tokenId = REGISTRY.register(
            td.label,
            td.owner,
            IRegistry(td.subregistry),
            td.resolver,
            td.roleBitmap,
            td.expiry
        );
        emit NameInjected(tokenId, td.label);
    }

    /**
     * @dev Sync the renewal of a name with the L2 registry.
     *
     * @param tokenId The token ID of the name
     * @param newExpiry The new expiration timestamp
     */
    function syncRenewal(
        uint256 tokenId,
        uint64 newExpiry
    ) external virtual onlyRootRoles(BridgeRolesLib.ROLE_EJECTOR) {
        REGISTRY.renew(tokenId, newExpiry);
        emit RenewalSynchronized(tokenId, newExpiry);
    }

    ////////////////////////////////////////////////////////////////////////
    // Internal Functions
    ////////////////////////////////////////////////////////////////////////

    /// @dev `EjectionController._onEject()` implementation.
    function _onEject(TransferData[] memory tds) internal virtual override {
        for (uint256 i; i < tds.length; ++i) {
            TransferData memory td = tds[i];

            (uint256 tokenId, ) = REGISTRY.getNameData(td.label);
            // TODO: avoid small expiry ejections?

            // Check if name is locked (no assignees for ROLE_SET_SUBREGISTRY or ROLE_SET_SUBREGISTRY_ADMIN means locked)
            (uint256 count, ) = REGISTRY.getAssigneeCount(
                LibLabel.getCanonicalId(tokenId),
                RegistryRolesLib.ROLE_SET_SUBREGISTRY | RegistryRolesLib.ROLE_SET_SUBREGISTRY_ADMIN
            );
            if (count == 0) {
                revert LockedNameCannotBeEjected(tokenId);
            }

            // burn the token
            REGISTRY.burn(tokenId);

            // send the message to the bridge
            BRIDGE.sendMessage(BridgeEncoderLib.encodeEjection(td));
            emit NameEjected(tokenId, td.label);
        }
    }
}
