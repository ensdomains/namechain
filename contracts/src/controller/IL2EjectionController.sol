// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/**
 * @title IL2EjectionController
 * @dev Interface for the L2 ejection controller that facilitates migrations of names
 * between L2 and L1, as well as handling renewals. The controller is responsible
 * for cross-chain communication.
 */
interface IL2EjectionController {
    /**
     * @dev Called by the ETHRegistry when a user initiates a migration of a name
     * from L2 to L1. The controller is responsible for sending the cross-chain message
     * to L1 to complete the migration.
     *
     * @param tokenId The token ID of the name being migrated
     * @param l1Owner The address that will own the name on L1
     * @param l1Subregistry The subregistry address to use on L1
     * @param flags The flags to set on the name
     * @param expires The expiration timestamp of the name
     * @param data Extra data
     */
    function ejectToL1(uint256 tokenId, address l1Owner, address l1Subregistry, uint32 flags, uint64 expires, bytes memory data) external;

    /**
     * @dev Called by the cross-chain messaging system when a name is being migrated
     * from L1 to L2. This function should verify the message source and then call
     * the ETHRegistry to complete the migration.
     *
     * @param labelHash The keccak256 hash of the label
     * @param l2Owner The address that will own the name on L2
     * @param l2Subregistry The subregistry address to use on L2
     * @param data Extra data
     */
    function completeMigration(
        uint256 labelHash,
        address l2Owner,
        address l2Subregistry,
        bytes memory data
    ) external;

    /**
     * @dev Called when a name is renewed on L1. This function updates the expiration date on L2.
     *
     * @param tokenId The token ID of the name
     * @param newExpiry The new expiration timestamp
     */
    function syncRenewalFromL1(uint256 tokenId, uint64 newExpiry) external;
}
