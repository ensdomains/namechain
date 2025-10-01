// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/**
 * @title MigrationErrors
 * @dev Error definitions specific to migration operations
 */

/**
 * @dev Thrown when attempting to migrate a subdomain whose parent has not been migrated
 * @param name The DNS-encoded name being migrated
 * @param offset The byte offset where the parent domain starts in the name
 */
error ParentNotMigrated(bytes name, uint256 offset);

/**
 * @dev Thrown when attempting to register a label that has an emancipated NFT in the old system but hasn't been migrated
 * @param label The label that needs to be migrated first
 */
error LabelNotMigrated(string label);
