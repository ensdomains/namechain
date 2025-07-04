// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

interface IRegistryResolver {
    /// @notice Resolve `name` using `parentRegistry` using the labels after `nodeSuffix`.
    /// @notice Caller should enable EIP-3668.
    /// @param parentRegistry The parent registry contract.
    /// @param nodeSuffix The node corresponding to the parent registry contract.
    /// @param name The name to resolve.
    /// @param data The calldata.
    /// @return The abi-encoded response for the request.
    function resolveWithRegistry(
        address parentRegistry,
        bytes32 nodeSuffix,
        bytes calldata name,
        bytes calldata data
    ) external view returns (bytes memory);
}
