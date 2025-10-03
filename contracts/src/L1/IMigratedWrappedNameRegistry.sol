// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/**
 * @dev Interface for MigratedWrappedNameRegistry initialization and core functions
 */
interface IMigratedWrappedNameRegistry {
    // TODO: fix
    // @notice Deploys a new MigratedWrappedNameRegistry via VerifiableFactory
    // @dev The owner will have the specified roles on the deployed registry
    // @param factory The VerifiableFactory to use for deployment
    // @param implementation The implementation address for the proxy
    // @param owner The address that will own the deployed registry
    // @param ownerRoles The roles to grant to the owner
    // @param salt The salt for CREATE2 deployment
    // @param parentDnsEncodedName The DNS-encoded name of the parent domain
    // @return subregistry The address of the deployed registry

    struct Args {
        bytes32 parentNode;
        address owner;
        uint256 ownerRoles;
        address registrar;
    }

    function initialize(Args calldata args) external;
}
