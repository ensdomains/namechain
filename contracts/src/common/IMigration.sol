// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {MigrationData} from "./TransferData.sol";

/**
 * @dev Interface for the migration strategies that get used by MigrationController instances.
 */
interface IMigrationStrategy {
  function migrateLockedEthName(address registry, uint256 tokenId, MigrationData memory migrationData) external;
}