// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/**
 * @dev The data for inter-chain transfers of a name.
 */
struct TransferData {
    bytes name;
    address owner;
    address subregistry;
    address resolver;
    uint256 roleBitmap;
    uint64 expiry;
}

/**
 * @dev The data for v1 to v2 migrations of names.
 */
struct MigrationData {
    TransferData transferData;
    /**
     * @dev If true, the name is being migrated to L1. If false, the name is being migrated to L2.
     */
    bool toL1;
    /**
     * @dev (Optional) Salt for CREATE2 deployments.
     */
    uint256 salt;
}
