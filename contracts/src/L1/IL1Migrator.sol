// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {TransferData} from "../common/TransferData.sol";

/**
 * @dev Interface for registering a name on L1 when migrating from v1 to v2.
 *
 * This is a convenience that allows us to migrate names from v1 to v2 on L1 
 * without having to eject from L2 to L1 once the name is registered on L2.
 */
interface IL1Migrator {
    function migrateFromV1(TransferData memory transferData) external;
}
