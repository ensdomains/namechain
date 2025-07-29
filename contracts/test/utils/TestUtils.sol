// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {LibEACBaseRoles} from "../../src/common/EnhancedAccessControl.sol";

library TestUtils {
    uint256 constant ALL_ROLES = LibEACBaseRoles.ALL_ROLES;
}