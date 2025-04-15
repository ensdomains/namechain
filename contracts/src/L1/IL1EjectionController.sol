// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/**
 * @title IL1EjectionController
 * @dev Interface for the L1 ejection controller that facilitates migrations of names
 * between L1 and L2, as well as handling renewals. The controller is responsible
 * for cross-chain communication.
 */
interface IL1EjectionController {
    /**
     * @dev Called by the L1ETHRegistry when a user initiates a migration of a name
     * back to L2. The controller is responsible for sending the cross-chain message
     * to L2 to complete the migration.
     *
     * @param tokenId The token ID of the name being migrated
     * @param l2Owner The address that will own the name on L2
     * @param l2Subregistry The subregistry address to use on L2
     * @param data Extra data
     */
    function migrateToNamechain(uint256 tokenId, address l2Owner, address l2Subregistry, bytes memory data) external;

    /**
     * @dev Called by the cross-chain messaging system when a name is being ejected
     * from L2 to L1. This function should verify the message source and then call
     * the L1ETHRegistry to complete the ejection.
     *
     * @param labelHash The keccak256 hash of the label
     * @param l1Owner The address that will own the name on L1
     * @param l1Subregistry The subregistry address to use on L1
     * @param roleBitmap The roles to set on the name
     * @param expires The expiration timestamp of the name
     * @param data Extra data
     */
    function completeEjection(
        uint256 labelHash,
        address l1Owner,
        address l1Subregistry,
        uint256 roleBitmap,
        uint64 expires,
        bytes memory data
    ) external;

    /**
     * @dev Called when L2 notifies about a renewal. This function updates the expiration date on L1.
     *
     * @param tokenId The token ID of the name
     * @param newExpiry The new expiration timestamp
     */
    function syncRenewalFromL2(uint256 tokenId, uint64 newExpiry) external;
}
