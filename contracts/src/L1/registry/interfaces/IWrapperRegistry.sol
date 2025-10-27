// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IPermissionedRegistry} from "../../../common/registry/interfaces/IPermissionedRegistry.sol";

/// @dev Size of `abi.encode(Data({...}))`.
uint256 constant DATA_SIZE = 128;

/// @dev Interface for a registry that manages a locked NameWrapper name.
interface IWrapperRegistry is IPermissionedRegistry {
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
        //address registrar; const? setter?
        uint256 salt;
    }

    ////////////////////////////////////////////////////////////////////////
    // Functions
    ////////////////////////////////////////////////////////////////////////

    function initialize(ConstructorArgs calldata args) external;

    // function migrate(Data calldata md) external returns (uint256 tokenId);

    // function migrate(Data[] calldata mds) external;

    // function parentNode() external view returns (bytes32);

    function parentName() external view returns (bytes memory);
}
