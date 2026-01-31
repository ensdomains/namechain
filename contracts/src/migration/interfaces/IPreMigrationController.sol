// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IRegistry} from "../../registry/interfaces/IRegistry.sol";

interface IPreMigrationController {
    /// @notice Claim a pre-migrated name (called by migration controllers)
    /// @param label The label of the name being claimed
    /// @param owner The new owner of the name
    /// @param subregistry The subregistry to set for the name
    /// @param resolver The resolver to set for the name
    /// @param roleBitmap The roles to grant to the owner
    function claim(
        string calldata label,
        address owner,
        IRegistry subregistry,
        address resolver,
        uint256 roleBitmap
    ) external;
}
