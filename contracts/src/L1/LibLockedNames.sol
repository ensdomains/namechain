// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {
    INameWrapper,
    CANNOT_UNWRAP,
    CANNOT_BURN_FUSES,
    CANNOT_TRANSFER,
    CANNOT_SET_RESOLVER,
    CANNOT_SET_TTL,
    CANNOT_CREATE_SUBDOMAIN,
    IS_DOT_ETH,
    CAN_EXTEND_EXPIRY,
    PARENT_CANNOT_CONTROL
} from "@ens/contracts/wrapper/INameWrapper.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";

import {LibRegistryRoles} from "./../common/LibRegistryRoles.sol";
import {IMigratedWrapperRegistry} from "./IMigratedWrapperRegistry.sol";

/**
 * @title LibLockedNames
 * @notice Library for common locked name migration operations
 * @dev Contains shared logic for migrating locked names from ENS NameWrapper to v2 registries
 */
library LibLockedNames {
    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice The fuses to burn during migration to prevent further changes
     * @dev Includes all transferable and modifiable fuses including the lock fuse
     */
    uint32 public constant FUSES_TO_BURN =
        CANNOT_UNWRAP |
            CANNOT_BURN_FUSES |
            CANNOT_TRANSFER |
            CANNOT_SET_RESOLVER |
            CANNOT_SET_TTL |
            CANNOT_CREATE_SUBDOMAIN;

    ////////////////////////////////////////////////////////////////////////
    // Library Functions
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Freezes a name by clearing its resolver if possible and burning all migration fuses
     * @dev Sets resolver to address(0) if CANNOT_SET_RESOLVER is not burned, then permanently freezes the name
     * @param nameWrapper The NameWrapper contract
     * @param tokenId The token ID to freeze
     * @param fuses The current fuses on the name
     */
    function freezeName(INameWrapper nameWrapper, uint256 tokenId, uint32 fuses) internal {
        // Clear resolver if CANNOT_SET_RESOLVER fuse is not set
        if ((fuses & CANNOT_SET_RESOLVER) == 0) {
            nameWrapper.setResolver(bytes32(tokenId), address(0));
        }

        // Burn all migration fuses
        nameWrapper.setFuses(bytes32(tokenId), uint16(FUSES_TO_BURN));
    }

    /**
     * @notice Generates role bitmaps based on fuses
     * @dev Returns two bitmaps: tokenRoles for the name registration and subRegistryRoles for the registry owner
     * @param fuses The current fuses on the name
     * @return tokenRoles The role bitmap for the owner on their name in their parent registry.
     * @return subRegistryRoles The role bitmap for the owner on their name's subregistry.
     */
    function generateRoleBitmapsFromFuses(
        uint32 fuses
    ) internal pure returns (uint256 tokenRoles, uint256 subRegistryRoles) {
        // Check if fuses are permanently frozen
        bool fusesFrozen = (fuses & CANNOT_BURN_FUSES) != 0;

        tokenRoles |=
            LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER |
            LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER_ADMIN;

        // Include renewal permissions if expiry can be extended
        if ((fuses & CAN_EXTEND_EXPIRY) != 0) {
            tokenRoles |= LibRegistryRoles.ROLE_RENEW;
            if (!fusesFrozen) {
                tokenRoles |= LibRegistryRoles.ROLE_RENEW_ADMIN;
            }
        }

        // Conditionally add resolver roles
        if ((fuses & CANNOT_SET_RESOLVER) == 0) {
            tokenRoles |= LibRegistryRoles.ROLE_SET_RESOLVER;
            if (!fusesFrozen) {
                tokenRoles |= LibRegistryRoles.ROLE_SET_RESOLVER_ADMIN;
            }
        }

        // Add transfer admin role if transfers are allowed
        if ((fuses & CANNOT_TRANSFER) == 0) {
            tokenRoles |= LibRegistryRoles.ROLE_CAN_TRANSFER_ADMIN;
        }

        // Owner gets registrar permissions on subregistry only if subdomain creation is allowed
        if ((fuses & CANNOT_CREATE_SUBDOMAIN) == 0) {
            subRegistryRoles |= LibRegistryRoles.ROLE_REGISTRAR;
            if (!fusesFrozen) {
                subRegistryRoles |= LibRegistryRoles.ROLE_REGISTRAR_ADMIN;
            }
        }

        // Add renewal roles to subregistry
        subRegistryRoles |= LibRegistryRoles.ROLE_RENEW;
        subRegistryRoles |= LibRegistryRoles.ROLE_RENEW_ADMIN;
    }
}
