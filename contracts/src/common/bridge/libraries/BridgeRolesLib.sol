// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @dev Library containing bridge-related role definitions
library BridgeRolesLib {
    uint256 internal constant ROLE_EJECTOR = 1 << 0;
    uint256 internal constant ROLE_EJECTOR_ADMIN = ROLE_EJECTOR << 128;
}
