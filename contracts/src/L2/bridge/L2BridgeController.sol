// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {BridgeController} from "../../common/bridge/BridgeController.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {IBridge} from "../../common/bridge/interfaces/IBridge.sol";
import {BridgeEncoderLib} from "../../common/bridge/libraries/BridgeEncoderLib.sol";
import {BridgeRolesLib} from "../../common/bridge/libraries/BridgeRolesLib.sol";
import {TransferData} from "../../common/bridge/types/TransferData.sol";
import {InvalidOwner} from "../../common/CommonErrors.sol";
import {IPermissionedRegistry} from "../../common/registry/interfaces/IPermissionedRegistry.sol";
import {IRegistry} from "../../common/registry/interfaces/IRegistry.sol";
import {IRegistryDatastore} from "../../common/registry/interfaces/IRegistryDatastore.sol";
import {ITokenObserver} from "../../common/registry/interfaces/ITokenObserver.sol";
import {RegistryRolesLib} from "../../common/registry/libraries/RegistryRolesLib.sol";

/**
 * @title L2BridgeController
 * @dev Combined controller that handles both ejection messages from L1 to L2 and ejection operations
 */
contract L2BridgeController is BridgeController, ITokenObserver {
    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    IRegistryDatastore public immutable DATASTORE;

    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    error NotTokenOwner(uint256 tokenId);

    error TooManyRoleAssignees(uint256 tokenId, uint256 roleBitmap);

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(
        IBridge bridge_,
        IPermissionedRegistry registry_,
        IRegistryDatastore datastore_
    ) BridgeController(registry_, bridge_) {
        DATASTORE = datastore_;
    }

    /// @inheritdoc BridgeController
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(BridgeController) returns (bool) {
        return
            interfaceId == type(ITokenObserver).interfaceId || super.supportsInterface(interfaceId);
    }

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    /**
     * @dev Should be called when a name is being ejected to L2.
     *
     * @param transferData The transfer data for the name being migrated
     */
    function completeEjectionToL2(
        TransferData calldata transferData
    ) external virtual onlyRootRoles(BridgeRolesLib.ROLE_EJECTOR) {
        (bytes32 labelHash, ) = NameCoder.readLabel(transferData.dnsEncodedName, 0);
        uint256 tokenId = REGISTRY.getTokenId(uint256(labelHash));

        // owner should be the bridge controller
        if (REGISTRY.ownerOf(tokenId) != address(this)) {
            revert NotTokenOwner(tokenId);
        }

        REGISTRY.setSubregistry(tokenId, IRegistry(transferData.subregistry));
        REGISTRY.setResolver(tokenId, transferData.resolver);

        // Clear token observer and transfer ownership to recipient
        REGISTRY.setTokenObserver(tokenId, ITokenObserver(address(0)));
        REGISTRY.safeTransferFrom(address(this), transferData.owner, tokenId, 1, "");

        emit NameEjectedToL2(transferData.dnsEncodedName, tokenId);
    }

    /**
     * @dev Override onERC1155Received to handle minting scenarios
     * When from is address(0), it's a mint operation and we should just return success
     * Otherwise, delegate to the parent implementation for ejection processing
     */
    function onERC1155Received(
        address /* operator */,
        address from,
        uint256 tokenId,
        uint256 /* amount */,
        bytes calldata data
    ) external virtual override onlyRegistry returns (bytes4) {
        // If from is not address(0), it's not a mint operation - process as ejection
        if (from != address(0)) {
            _processEjection(tokenId, data);
        }

        return this.onERC1155Received.selector;
    }

    /**
     * @dev Default implementation of onRenew that does nothing.
     * Can be overridden in derived contracts for custom behavior.
     */
    function onRenew(
        uint256 tokenId,
        uint64 expires,
        address /*renewedBy*/
    ) external virtual onlyRegistry {
        BRIDGE.sendMessage(BridgeEncoderLib.encodeRenewal(tokenId, expires));
    }

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

            // check that the owner is not null address
            if (transferData.owner == address(0)) {
                revert InvalidOwner();
            }

            // check that the label matches the token id
            _assertTokenIdMatchesLabel(tokenId, transferData.dnsEncodedName);

            /*
            Check that there is no more than one holder of the token observer and subregistry setting roles.

            This works by calculating the no. of assignees for each of the given roles as a bitmap `(counts & mask)` where each role's corresponding 
            nybble is set to its assignee count.

            Since the roles themselves are bitmaps where each role's nybble is set to 1, we can simply comparing the two values to 
            check to see if each role has exactly one assignee.

            We also don't need to check that we (the bridge controller) are the sole assignee of these roles since we exercise these 
            roles further down below.
            */
            uint256 roleBitmap = RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER |
                RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER_ADMIN |
                RegistryRolesLib.ROLE_SET_SUBREGISTRY |
                RegistryRolesLib.ROLE_SET_SUBREGISTRY_ADMIN |
                RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN;
            (uint256 counts, uint256 mask) = REGISTRY.getAssigneeCount(tokenId, roleBitmap);
            if (counts & mask != roleBitmap) {
                revert TooManyRoleAssignees(tokenId, roleBitmap);
            }

            // NOTE: we don't nullify the resolver here, so that there is no resolution downtime
            REGISTRY.setSubregistry(tokenId, IRegistry(address(0)));
            REGISTRY.setTokenObserver(tokenId, this);

            // Send bridge message for ejection
            BRIDGE.sendMessage(BridgeEncoderLib.encodeEjection(transferData));
            emit NameEjectedToL1(transferData.dnsEncodedName, tokenId);
        }
    }
}
