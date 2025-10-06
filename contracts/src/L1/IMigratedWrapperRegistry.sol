// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";

/// @dev Interface for IMigratedWrapperRegistry initialization and core functions
interface IMigratedWrapperRegistry is IPermissionedRegistry {
    ////////////////////////////////////////////////////////////////////////
    // Types
    ////////////////////////////////////////////////////////////////////////

    struct ConstructorArgs {
        bytes32 parentNode;
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

    // TODO: fix
    // @notice Deploys a new IMigratedWrapperRegistry via VerifiableFactory
    // @dev The owner will have the specified roles on the deployed registry
    // @param factory The VerifiableFactory to use for deployment
    // @param implementation The implementation address for the proxy
    // @param owner The address that will own the deployed registry
    // @param ownerRoles The roles to grant to the owner
    // @param salt The salt for CREATE2 deployment
    // @param parentDnsEncodedName The DNS-encoded name of the parent domain
    // @return subregistry The address of the deployed registry

    function initialize(ConstructorArgs calldata args) external;

    // TODO: rename to baseNode() and baseName() ?
    function parentNode() external view returns (bytes32);

    function parentName() external view returns (bytes memory);

    function migrate(Data calldata md) external returns (uint256 tokenId);

    function migrate(Data[] calldata mds) external;
}
