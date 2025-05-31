// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

bytes32 constant NODE_ANY = 0;

/// @notice Resolver profile that signals it returns the same results for all supported names. 
interface IDedicatedResolver {
    /// @dev Check if name is supported.
    /// @param name The DNS-encoded name to check.
    /// @return supported True if the name is supported.
    function supportsName(bytes memory name) external view returns (bool supported);
}
