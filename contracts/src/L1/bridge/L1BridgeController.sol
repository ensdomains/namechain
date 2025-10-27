// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {AbstractBridgeController} from "../../common/bridge/AbstractBridgeController.sol";
import {IBridge} from "../../common/bridge/interfaces/IBridge.sol";
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
contract L1BridgeController is AbstractBridgeController {
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
    ) AbstractBridgeController(registry, bridge) {}

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

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

    function _inject(TransferData memory td) internal override returns (uint256 tokenId) {
        tokenId = REGISTRY.register(
            td.label,
            td.owner,
            td.subregistry,
            td.resolver,
            td.roleBitmap,
            td.expiry
        );
    }

    function _eject(uint256 tokenId, TransferData memory /*td*/) internal override {
        // we're in the middle of a transfer
        // we currently own the token
        // we need to block locked wrapped names
        if (
            REGISTRY.hasRoles(tokenId, RegistryRolesLib.ROLE_SET_SUBREGISTRY_ADMIN, address(this))
        ) {
            revert LockedNameCannotBeEjected(tokenId);
        }
        // burn the token but keep the registry/resolver
        REGISTRY.burn(tokenId, true);
    }
}
