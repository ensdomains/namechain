// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/// @dev Placeholder node for compatibility with standard resolver behavior.
bytes32 constant NODE_ANY = 0;

/// @notice Interface for a resolver that returns the same records for all names.
/// @dev Interface selector: `0x03da7680`
interface ISingularResolver {
    /// @dev Dummy function to populate the interface.
    function __ISingularResolver() external pure;
}
