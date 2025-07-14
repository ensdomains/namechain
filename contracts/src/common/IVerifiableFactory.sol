// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/**
 * @title IVerifiableFactory
 * @dev Interface for deploying verifiable proxy contracts
 */
interface IVerifiableFactory {
    /**
     * @dev Deploys a new proxy contract at a deterministic address.
     * @param implementation The address of the contract implementation the proxy will delegate calls to.
     * @param salt A value provided by the caller to ensure uniqueness of the proxy address.
     * @param data Initialization data to be passed to the proxy's initialize function.
     * @return The address of the deployed proxy.
     */
    function deployProxy(address implementation, uint256 salt, bytes memory data) external returns (address);
} 