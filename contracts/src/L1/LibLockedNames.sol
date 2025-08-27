// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {INameWrapper, CANNOT_UNWRAP, CANNOT_BURN_FUSES, CANNOT_TRANSFER, CANNOT_SET_RESOLVER, CANNOT_SET_TTL, CANNOT_CREATE_SUBDOMAIN, CANNOT_APPROVE, IS_DOT_ETH, CAN_EXTEND_EXPIRY} from "@ens/contracts/wrapper/INameWrapper.sol";
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
     * @param parentDnsEncodedName The DNS-encoded name of the parent domain
     * @return subregistry The address of the deployed registry
     */
    function deployMigratedRegistry(
        VerifiableFactory factory,
        address implementation,
        address owner,
        uint256 salt,
        bytes memory parentDnsEncodedName
    ) internal returns (address subregistry) {
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,bytes)",
            owner,
            parentDnsEncodedName
        );
        subregistry = factory.deployProxy(implementation, salt, initData);
    }

    /**
     * @notice Generates the role bitmap based on fuses
     * @dev Conditionally adds RENEW and RESOLVER roles based on fuses
     * @param fuses The current fuses on the name
     * @return roleBitmap The generated role bitmap
     */
    function generateRoleBitmapFromFuses(uint32 fuses) internal pure returns (uint256 roleBitmap) {
        // Add ROLE_RENEW only if CAN_EXTEND_EXPIRY fuse is set
        if ((fuses & CAN_EXTEND_EXPIRY) != 0) {
            roleBitmap |= LibRegistryRoles.ROLE_RENEW;
        }
        
        // Add ROLE_RENEW_ADMIN only if CANNOT_APPROVE fuse is not set
        if ((fuses & CANNOT_APPROVE) == 0) {
            roleBitmap |= LibRegistryRoles.ROLE_RENEW_ADMIN;
        }
        
        // Conditionally add resolver roles
        if ((fuses & CANNOT_SET_RESOLVER) == 0) {
            roleBitmap |= LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_SET_RESOLVER_ADMIN;
        }
    }

    /**
     * @notice Burns all migration fuses on a NameWrapper token
     * @dev Burns all fuses except CANNOT_UNWRAP (already set) to prevent further changes
     * @param nameWrapper The NameWrapper contract
     * @param tokenId The token ID to burn fuses on
     */
    function burnAllFuses(INameWrapper nameWrapper, uint256 tokenId) internal {
        nameWrapper.setFuses(bytes32(tokenId), uint16(MIGRATION_FUSES_TO_BURN));
    }
}