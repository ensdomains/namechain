// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {INameWrapper, CANNOT_UNWRAP, CANNOT_BURN_FUSES, CANNOT_TRANSFER, CANNOT_SET_RESOLVER, CANNOT_SET_TTL, CANNOT_CREATE_SUBDOMAIN, CANNOT_APPROVE, IS_DOT_ETH} from "@ens/contracts/wrapper/INameWrapper.sol";
import {LibRegistryRoles} from "../common/LibRegistryRoles.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {IUniversalResolver} from "@ens/contracts/universalResolver/IUniversalResolver.sol";
import {VerifiableFactory} from "../../lib/verifiable-factory/src/VerifiableFactory.sol";

/**
 * @title LibLockedNames
 * @notice Library for common locked name migration operations
 * @dev Contains shared logic for migrating locked names from ENS NameWrapper to v2 registries
 */
library LibLockedNames {
    error NameNotLocked(uint256 tokenId);
    error InconsistentFusesState(uint256 tokenId);
    error NotDotEthName(uint256 tokenId);

    /**
     * @notice The fuses to burn during migration to prevent further changes
     * @dev Includes all fuses except CANNOT_UNWRAP (already set) and IS_DOT_ETH (informational)
     */
    uint32 public constant MIGRATION_FUSES_TO_BURN = 
        CANNOT_BURN_FUSES |
        CANNOT_TRANSFER |
        CANNOT_SET_RESOLVER |
        CANNOT_SET_TTL |
        CANNOT_CREATE_SUBDOMAIN |
        CANNOT_APPROVE;

    /**
     * @notice Validates that a name is properly locked for migration
     * @dev Checks that CANNOT_UNWRAP is set and CANNOT_BURN_FUSES is not set
     * @param fuses The current fuses on the name
     * @param tokenId The token ID for error reporting
     */
    function validateLockedName(uint32 fuses, uint256 tokenId) internal pure {
        // Combined validation: CANNOT_UNWRAP must be set, CANNOT_BURN_FUSES must not be set
        uint32 requiredState = fuses & (CANNOT_UNWRAP | CANNOT_BURN_FUSES);
        
        if (requiredState != CANNOT_UNWRAP) {
            if ((fuses & CANNOT_UNWRAP) == 0) {
                revert NameNotLocked(tokenId);
            }
            // If we reach here, CANNOT_BURN_FUSES must be set
            revert InconsistentFusesState(tokenId);
        }
    }

    /**
     * @notice Validates that a name is a .eth second-level domain
     * @dev Checks the IS_DOT_ETH fuse, which is only valid for .eth 2LDs
     * @param fuses The current fuses on the name
     * @param tokenId The token ID for error reporting
     */
    function validateIsDotEth2LD(uint32 fuses, uint256 tokenId) internal pure {
        if ((fuses & IS_DOT_ETH) == 0) {
            revert NotDotEthName(tokenId);
        }
    }

    /**
     * @notice Deploys a new MigratedWrappedNameRegistry via VerifiableFactory
     * @dev The owner will have REGISTRAR and REGISTRAR_ADMIN roles on the deployed registry
     * @param factory The VerifiableFactory to use for deployment
     * @param implementation The implementation address for the proxy
     * @param owner The address that will own the deployed registry
     * @param salt The salt for CREATE2 deployment
     * @return subregistry The address of the deployed registry
     */
    function deployMigratedRegistry(
        VerifiableFactory factory,
        address implementation,
        address owner,
        uint256 salt
    ) internal returns (address subregistry) {
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,uint256)",
            owner,
            LibRegistryRoles.ROLE_REGISTRAR | LibRegistryRoles.ROLE_REGISTRAR_ADMIN
        );
        subregistry = factory.deployProxy(implementation, salt, initData);
    }

    /**
     * @notice Generates the role bitmap based on fuses
     * @dev Always includes RENEW roles, conditionally adds RESOLVER and REGISTRAR roles
     * @param fuses The current fuses on the name
     * @param isSubdomain Whether this is for a subdomain (affects REGISTRAR role assignment)
     * @return roleBitmap The generated role bitmap
     */
    function generateRoleBitmapFromFuses(uint32 fuses, bool isSubdomain) internal pure returns (uint256 roleBitmap) {
        uint256 resolverRoles = LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_RESOLVER_ADMIN;
        uint256 registrarRoles = LibRegistryRoles.ROLE_REGISTRAR | LibRegistryRoles.ROLE_REGISTRAR_ADMIN;
        
        // Start with renew roles (always granted)
        roleBitmap = LibRegistryRoles.ROLE_RENEW | LibRegistryRoles.ROLE_RENEW_ADMIN;
        
        // Conditionally add resolver roles
        if ((fuses & CANNOT_SET_RESOLVER) == 0) {
            roleBitmap |= resolverRoles;
        }
        
        // Conditionally add registrar roles for subdomains
        if (isSubdomain && (fuses & CANNOT_CREATE_SUBDOMAIN) == 0) {
            roleBitmap |= registrarRoles;
        }
    }

    /**
     * @notice Burns all migration fuses on a NameWrapper token
     * @dev Burns all fuses except CANNOT_UNWRAP (already set) to prevent further changes
     * @param nameWrapper The NameWrapper contract
     * @param tokenId The token ID to burn fuses on
     */
    function burnAllMigrationFuses(INameWrapper nameWrapper, uint256 tokenId) internal {
        nameWrapper.setFuses(bytes32(tokenId), uint16(MIGRATION_FUSES_TO_BURN));
    }
}