// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {EjectionController} from "../../common/bridge/EjectionController.sol";
import {IBridge} from "../../common/bridge/interfaces/IBridge.sol";
import {BridgeEncoderLib} from "../../common/bridge/libraries/BridgeEncoderLib.sol";
import {BridgeRolesLib} from "../../common/bridge/libraries/BridgeRolesLib.sol";
import {TransferData} from "../../common/bridge/types/TransferData.sol";
import {IPermissionedRegistry} from "../../common/registry/interfaces/IPermissionedRegistry.sol";
import {IRegistry} from "../../common/registry/interfaces/IRegistry.sol";
import {IRegistryDatastore} from "../../common/registry/interfaces/IRegistryDatastore.sol";
import {ITokenObserver} from "../../common/registry/interfaces/ITokenObserver.sol";
import {RegistryRolesLib} from "../../common/registry/libraries/RegistryRolesLib.sol";

/**
 * @title L2BridgeController
 * @dev Combined controller that handles both ejection messages from L1 to L2 and ejection operations
 */
contract L2BridgeController is EjectionController, ITokenObserver {
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
        IBridge bridge,
        IPermissionedRegistry registry,
        IRegistryDatastore datastore
    ) EjectionController(registry, bridge) {
        DATASTORE = datastore;
    }

    /// @inheritdoc EjectionController
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(EjectionController) returns (bool) {
        return
            interfaceId == type(ITokenObserver).interfaceId || super.supportsInterface(interfaceId);
    }

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    /**
     * @dev Default implementation of onRenew that does nothing.
     * Can be overridden in derived contracts for custom behavior.
     */
    function onRenew(
        uint256 tokenId,
        uint64 expiry,
        address /*renewedBy*/
    ) external virtual onlyRegistry {
        BRIDGE.sendMessage(BridgeEncoderLib.encodeRenewal(tokenId, expiry));
    }

    /**
     * @dev Should be called when a name is being ejected to L2.
     *
     * @param td The transfer data for the name being migrated
     */
    function completeEjectionToL2(
        TransferData calldata td
    ) external virtual onlyRootRoles(BridgeRolesLib.ROLE_EJECTOR) {
        (uint256 tokenId, ) = REGISTRY.getNameData(td.label);

        // owner should be the bridge controller
        if (REGISTRY.ownerOf(tokenId) != address(this)) {
            revert NotTokenOwner(tokenId);
        }

        REGISTRY.setSubregistry(tokenId, IRegistry(td.subregistry));
        REGISTRY.setResolver(tokenId, td.resolver);

        // Clear token observer and transfer ownership to recipient
        REGISTRY.setTokenObserver(tokenId, ITokenObserver(address(0)));
        REGISTRY.safeTransferFrom(address(this), td.owner, tokenId, 1, "");

        emit NameInjected(tokenId, td.label);
    }

    /// @dev Override onERC1155Received to handle minting.
    function onERC1155Received(
        address operator,
        address from,
        uint256 tokenId,
        uint256 amount,
        bytes calldata data
    ) public virtual override onlyRegistry returns (bytes4) {
        if (from == address(0)) {
            // When from is address(0), it's a mint operation and we should just return success
            // TODO: when does this happen?
            return this.onERC1155Received.selector;
        }
        return super.onERC1155Received(operator, from, tokenId, amount, data);
    }

    /// @dev `EjectionController._onEject()` implementation.
    function _onEject(TransferData[] memory tds) internal virtual override {
        for (uint256 i; i < tds.length; ++i) {
            TransferData memory td = tds[i];

            (uint256 tokenId, ) = REGISTRY.getNameData(td.label);

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
            BRIDGE.sendMessage(BridgeEncoderLib.encodeEjection(td));
            emit NameEjected(tokenId, td.label);
        }
    }
}
