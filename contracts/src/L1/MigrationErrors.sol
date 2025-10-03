// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/**
 * @title MigrationErrors
 * @dev Error definitions specific to migration operations
 */

library MigrationErrors {
    /**
     * @dev Thrown when attempting to migrate a subdomain whose parent has not been migrated
     * @param name The DNS-encoded name being migrated
     */
    error NameNotMigrated(bytes name);
    error NameNotSubdomain(bytes childName, bytes parentName);

    error NodeMismatch(bytes32 tokenNode, bytes32 transferNode);
    error NameIsLocked(bytes name);
    error NameNotLocked(bytes name);
    error NameNotETH2LD(bytes name);
}
