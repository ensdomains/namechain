// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

interface IRemoteRegistryResolver {
    /// @notice Resolve `name` using `remoteRegistry` on another chain using the labels after `nodeSuffix`.
    /// @notice Caller should enable EIP-3668.
    /// @param remoteRegistry The registry contract on another chain.
    /// @param nodeSuffix The node corresponding to the registry contract.
    /// @param name The name to resolve.
    /// @param data The calldata.
    /// @return The abi-encoded response for the request.
    function resolveWithRegistry(
        address remoteRegistry,
        bytes32 nodeSuffix,
        bytes calldata name,
        bytes calldata data
    ) external view returns (bytes memory);
}
