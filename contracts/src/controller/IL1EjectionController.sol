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
     * @dev Event emitted when a name is ready to migrate from L1 to L2
     * @param tokenId The token ID of the name being migrated
     * @param l2Owner The address that will own the name on L2
     * @param l2Subregistry The subregistry address to use on L2
     */
    event NameMigratingToL2(uint256 indexed tokenId, address l2Owner, address l2Subregistry);

    /**
     * @dev Event emitted when a name has been ejected from L2 to L1
     * @param tokenId The token ID of the ejected name
     * @param l1Owner The address that owns the name on L1
     * @param l1Subregistry The subregistry address used on L1
     * @param expires The expiration timestamp of the name
     */
    event NameEjectedFromL2(uint256 indexed tokenId, address l1Owner, address l1Subregistry, uint64 expires);

    /**
     * @dev Event emitted when a name is renewed on L1, and L2 needs to be updated
     * @param tokenId The token ID of the name
     * @param newExpiry The new expiration timestamp
     */
    event NameRenewedOnL1(uint256 indexed tokenId, uint64 newExpiry);

    /**
     * @dev Called by the L1ETHRegistry when a user initiates a migration of a name
     * back to L2. The controller is responsible for sending the cross-chain message
     * to L2 to complete the migration.
     *
     * @param tokenId The token ID of the name being migrated
     * @param l2Owner The address that will own the name on L2
     * @param l2Subregistry The subregistry address to use on L2
     */
    function initiateL1ToL2Migration(uint256 tokenId, address l2Owner, address l2Subregistry) external;

    /**
     * @dev Called by the cross-chain messaging system when a name is being ejected
     * from L2 to L1. This function should verify the message source and then call
     * the L1ETHRegistry to complete the ejection.
     *
     * @param labelHash The keccak256 hash of the label
     * @param l1Owner The address that will own the name on L1
     * @param l1Subregistry The subregistry address to use on L1
     * @param flags The flags to set on the name
     * @param expires The expiration timestamp of the name
     */
    function completeL2ToL1Ejection(
        uint256 labelHash,
        address l1Owner,
        address l1Subregistry,
        uint32 flags,
        uint64 expires
    ) external;

    /**
     * @dev Called after a name is renewed on L1 to notify L2 about the renewal.
     * This function initiates a cross-chain message to update the expiration on L2.
     *
     * @param tokenId The token ID of the name
     * @param newExpiry The new expiration timestamp
     */
    function syncRenewalToL2(uint256 tokenId, uint64 newExpiry) external;
}
