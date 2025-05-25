// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/**
  * @dev The data for a migration.
  * This will be passed in the data field of the ERC1155Received or ERC1155BatchReceived calls.
  */
struct MigrationData {
    /**
      * @dev The label of the .eth name.
      */
    string label;
}


/**
 * @dev Interface for the migration strategies that get used by MigrationController instances.
 */
interface IMigrationStrategy {
  function migrateWrappedEthNames(address registry, uint256[] memory tokenIds, MigrationData[] memory migrationDataArray) external;
}