// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IEjectionController} from "../common/IEjectionController.sol";

/**
 * @title IL1EjectionController
 * @dev Interface for the L1 ejection controller that facilitates migrations of names
 * between L1 and L2, as well as handling renewals. 
 */
interface IL1EjectionController is IEjectionController {
    /**
     * @dev Called by the registry when a user initiates a migration of a name to Namechain.
     *
     * @param tokenId The token ID of the name being migrated
     * @param newOwner The address that will own the name on Namechain    
     * @param newSubregistry The subregistry address to use on Namechain
     * @param newResolver The resolver address to use on Namechain
     * @param data Extra data
     */
    function migrateToNamechain(uint256 tokenId, address newOwner, address newSubregistry, address newResolver, bytes memory data) external;

    /**
     * @dev Called by the cross-chain messaging system when a name has being ejected to this chain from Namechain.
     *
     * @param tokenId The token ID of the name
     * @param newOwner The address that will own the name on this chain
     * @param newSubregistry The subregistry address to use on this chain
     * @param newResolver The resolver address to use on this chain
     * @param expires The expiration timestamp of the name
     * @param data Extra data
     */
    function completeEjectionFromNamechain(
        uint256 tokenId,
        address newOwner,
        address newSubregistry,
        address newResolver,
        uint64 expires,
        bytes memory data
    ) external;

    /**
     * @dev Called when Namechain notifies about a renewal.
     *
     * @param tokenId The token ID of the name
     * @param newExpiry The new expiration timestamp
     */
    function syncRenewal(uint256 tokenId, uint64 newExpiry) external;
}
