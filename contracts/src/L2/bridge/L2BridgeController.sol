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

/// @dev A subset of the roles assigned by `ETHRegistrar.register()` required to bridge.
uint256 constant REQUIRED_EJECTION_ROLES = 0 |
    RegistryRolesLib.ROLE_SET_RESOLVER |
    // RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN | // technically, not required
    RegistryRolesLib.ROLE_SET_SUBREGISTRY |
    RegistryRolesLib.ROLE_SET_SUBREGISTRY_ADMIN |
    RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER |
    RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER_ADMIN |
    RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN;

uint256 constant ASSIGNED_INJECTION_ROLES = 0 |
    RegistryRolesLib.ROLE_SET_RESOLVER |
    RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN |
    RegistryRolesLib.ROLE_SET_SUBREGISTRY |
    RegistryRolesLib.ROLE_SET_SUBREGISTRY_ADMIN |
    RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN;

address constant POST_MIGRATION_RESOLVER = address(2); // ETHTLDResolver.NameState.POST_MIGRATION

/**
 * @title L2BridgeController
 * @dev Combined controller that handles both ejection messages from L1 to L2 and ejection operations
 */
contract L2BridgeController is AbstractBridgeController, ITokenObserver {
    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    error NotTokenOwner(uint256 tokenId);

    error TooManyRoleAssignees(uint256 tokenId, uint256 roleBitmap, uint256 counts);

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(
        IBridge bridge,
        IPermissionedRegistry registry
    ) AbstractBridgeController(bridge, registry) {}

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

        if (REGISTRY.ownerOf(tokenId) != address(this)) {
            revert NotTokenOwner(tokenId); // likely expired inflight
        }

        REGISTRY.setResolver(tokenId, td.resolver);
        REGISTRY.setSubregistry(tokenId, td.subregistry);
        REGISTRY.setTokenObserver(tokenId, ITokenObserver(address(0)));
        // td.expiry is ignored
        // td.roleBitmap is ignored

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
        (uint256 counts, uint256 mask) = REGISTRY.getAssigneeCount(
            tokenId,
            REQUIRED_EJECTION_ROLES
        );
        counts &= mask;
        if (counts != REQUIRED_EJECTION_ROLES) {
            revert TooManyRoleAssignees(tokenId, REQUIRED_EJECTION_ROLES, counts);
        }

        // set to special value which indicates this name is inflight to Namechain
        // during L2 -> L1, injection will always? happen before L2 finality on L1.
        // during L1 -> L2, ejection instantly will lookup this resolver, and then continue using L1, until L2 injection happens.
        REGISTRY.setResolver(tokenId, POST_MIGRATION_RESOLVER);

        // relay renews to L1
        REGISTRY.setTokenObserver(tokenId, this);

        td.expiry = REGISTRY.getExpiry(tokenId);
        td.roleBitmap = ASSIGNED_INJECTION_ROLES;
    }
}
