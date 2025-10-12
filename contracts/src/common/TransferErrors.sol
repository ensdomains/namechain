// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/// @dev Errors for bridge and migration process.
library TransferErrors {
    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    string constant ERROR_ONLY_NAME_WRAPPER = "expected NameWrapper";
    string constant ERROR_ONLY_ETH_REGISTRAR = "expected BaseRegistrarImplementation";
    string constant ERROR_UNEXPECTED_TRANSFER = "unexpected migration via transfer()";

    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    /// @dev Thrown when attempting to migrate a subdomain whose parent has not been migrated
    /// @param name The DNS-encoded name being migrated.
    error NameNotMigrated(bytes name);
    error NameNotSubdomain(bytes name, bytes parentName);

    error NameIsLocked(bytes name);
    error NameNotLocked(bytes name);
    error NameNotETH2LD(bytes name);
    error NameNotEmancipated(bytes name);

    error InvalidTransferData();
    error InvalidTransferOwner();
    error InvalidTransferAmount();

    error TokenNodeMismatch(uint256 tokenId, bytes32 node);
}
