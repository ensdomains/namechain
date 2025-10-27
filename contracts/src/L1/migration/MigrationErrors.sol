// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/// @dev Errors for migration process.
library MigrationErrors {
    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    error NameNotMigrated(bytes name);
    error NameNotSubdomain(bytes name, bytes parentName);

    error NameIsLocked(bytes name);
    error NameNotLocked(bytes name);
    error NameNotETH2LD(bytes name);
    error NameNotEmancipated(bytes name);

    error InvalidWrapperRegistryData();

    error TokenNodeMismatch(uint256 tokenId, bytes32 node);
}
