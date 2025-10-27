// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {AbstractBridgeController} from "../../common/bridge/AbstractBridgeController.sol";
import {IBridge} from "../../common/bridge/interfaces/IBridge.sol";
import {BridgeEncoderLib} from "../../common/bridge/libraries/BridgeEncoderLib.sol";
import {TransferData} from "../../common/bridge/types/TransferData.sol";
import {IPermissionedRegistry} from "../../common/registry/interfaces/IPermissionedRegistry.sol";
import {IRegistryDatastore} from "../../common/registry/interfaces/IRegistryDatastore.sol";
import {ITokenObserver} from "../../common/registry/interfaces/ITokenObserver.sol";
import {RegistryRolesLib} from "../../common/registry/libraries/RegistryRolesLib.sol";

/**
 * @title L2BridgeController
 * @dev Combined controller that handles both ejection messages from L1 to L2 and ejection operations
 */
contract L2BridgeController is AbstractBridgeController, ITokenObserver {
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
    ) AbstractBridgeController(registry, bridge) {
        DATASTORE = datastore;
    }

    /// @inheritdoc AbstractBridgeController
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
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

    function _inject(TransferData memory td) internal override returns (uint256 tokenId) {
        (tokenId, ) = REGISTRY.getNameData(td.label);

        // owner should be the bridge controller
        if (REGISTRY.ownerOf(tokenId) != address(this)) {
            revert NotTokenOwner(tokenId);
        }

        REGISTRY.setSubregistry(tokenId, td.subregistry);
        REGISTRY.setResolver(tokenId, td.resolver);

        // Clear token observer and transfer ownership to recipient
        REGISTRY.setTokenObserver(tokenId, ITokenObserver(address(0)));
        REGISTRY.safeTransferFrom(address(this), td.owner, tokenId, 1, "");
    }

    function _eject(uint256 tokenId, TransferData memory td) internal override {
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

        // set to special value which indicates this name is inflight to Namechain
        // during L2 -> L1, injection will always? happen before L2 finality on L1.
        // during L1 -> L2, ejection instantly will lookup this resolver, and then continue using L1, until L2 injection happens.
        REGISTRY.setResolver(tokenId, address(2));

        REGISTRY.setTokenObserver(tokenId, this);

        td.expiry = REGISTRY.getExpiry(tokenId);
    }
}
