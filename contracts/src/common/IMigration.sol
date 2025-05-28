// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {TransferData} from "./TransferData.sol";

/**
 * @dev Interface for the migration strategies that get used by MigrationController instances.
 */
interface IMigrationStrategy {
  function migrateLockedEthName(address registry, uint256 tokenId, TransferData memory migrationData) external;
}