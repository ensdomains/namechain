// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IPermissionedRegistry} from "../../../common/registry/interfaces/IPermissionedRegistry.sol";

// TODO: rename parent* to base*?

/// @dev Interface for IMigratedWrappedNameRegistry initialization and core functions
interface IMigratedWrappedNameRegistry is IPermissionedRegistry {
    ////////////////////////////////////////////////////////////////////////
    // Types
    ////////////////////////////////////////////////////////////////////////

    struct ConstructorArgs {
        bytes32 node;
        address owner;
        uint256 ownerRoles;
        address registrar;
    }

    struct Data {
        bytes32 node;
        address owner;
        address resolver;
        uint256 salt;
    }

    ////////////////////////////////////////////////////////////////////////
    // Functions
    ////////////////////////////////////////////////////////////////////////

    function initialize(ConstructorArgs calldata args) external;

    function migrate(Data calldata md) external returns (uint256 tokenId);

    function migrate(Data[] calldata mds) external;

    function parentNode() external view returns (bytes32);

    function parentName() external view returns (bytes memory);
}
