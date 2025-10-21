// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IEnhancedAccessControl} from "../../access-control/interfaces/IEnhancedAccessControl.sol";

import {IRegistry} from "./IRegistry.sol";

interface IPermanentRegistry is IRegistry, IEnhancedAccessControl {
    function register(
        string calldata label,
        address operator,
        IRegistry subregistry,
        address resolver,
        uint256 roleBitmap,
        bool resetRoles
    ) external returns (uint256);
}
