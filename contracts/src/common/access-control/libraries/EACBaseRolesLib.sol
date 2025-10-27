// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library EACBaseRolesLib {
    uint256 public constant ALL_ROLES =
        0x1111111111111111111111111111111111111111111111111111111111111111;

    uint256 public constant ADMIN_ROLES =
        0x1111111111111111111111111111111100000000000000000000000000000000;

    /// @notice Returns the roles bitmap for all accounts in a resource.
    function rolesFromCount(uint256 count) internal pure returns (uint256) {
        return
            (count & ALL_ROLES) |
            ((count >> 1) & ALL_ROLES) |
            ((count >> 2) & ALL_ROLES) |
            ((count >> 3) & ALL_ROLES);
    }

    function adminRoles(uint256 roles) internal pure returns (uint256) {
        return roles >> 128;
    }
}
