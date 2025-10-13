// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

import {EjectionController} from "../../common/bridge/EjectionController.sol";
import {IBridge} from "../../common/bridge/interfaces/IBridge.sol";
import {BridgeEncoderLib} from "../../common/bridge/libraries/BridgeEncoderLib.sol";
import {BridgeRolesLib} from "../../common/bridge/libraries/BridgeRolesLib.sol";
import {TransferData} from "../../common/bridge/types/TransferData.sol";
import {InvalidOwner} from "../../common/CommonErrors.sol";
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

    error NotTokenOwner(uint256 tokenId);

    error LockedNameCannotBeEjected(uint256 tokenId);

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(
        IPermissionedRegistry registry_,
        IBridge bridge_
    ) EjectionController(registry_, bridge_) {}

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    /**
     * @dev Should be called when a name is being ejected to L1.
     *
     * @param transferData The transfer data for the name being ejected
     */
    function completeEjectionToL1(
        TransferData memory transferData
    ) external virtual onlyRootRoles(BridgeRolesLib.ROLE_EJECTOR) returns (uint256 tokenId) {
        string memory label = NameCoder.firstLabel(transferData.dnsEncodedName);

        tokenId = REGISTRY.register(
            label,
            transferData.owner,
            IRegistry(transferData.subregistry),
            transferData.resolver,
            transferData.roleBitmap,
            transferData.expires
        );
        emit NameEjectedToL1(transferData.dnsEncodedName, tokenId);
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

    /**
     * Overrides the EjectionController._onEject function.
     */
    function _onEject(
        uint256[] memory tokenIds,
        TransferData[] memory transferDataArray
    ) internal virtual override {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            TransferData memory transferData = transferDataArray[i];

            // Check if name is locked (no assignees for ROLE_SET_SUBREGISTRY or ROLE_SET_SUBREGISTRY_ADMIN means locked)
            uint256 resource = LibLabel.getCanonicalId(tokenId);
            (uint256 count, ) = REGISTRY.getAssigneeCount(
                resource,
                RegistryRolesLib.ROLE_SET_SUBREGISTRY | RegistryRolesLib.ROLE_SET_SUBREGISTRY_ADMIN
            );
            if (count == 0) {
                revert LockedNameCannotBeEjected(tokenId);
            }

            // check that the owner is not null address
            if (transferData.owner == address(0)) {
                revert InvalidOwner();
            }

            // check that the label matches the token id
            _assertTokenIdMatchesLabel(tokenId, transferData.dnsEncodedName);

            // burn the token
            REGISTRY.burn(tokenId);

            // send the message to the bridge
            BRIDGE.sendMessage(BridgeEncoderLib.encodeEjection(transferData));
            emit NameEjectedToL2(transferData.dnsEncodedName, tokenId);
        }
    }
}
