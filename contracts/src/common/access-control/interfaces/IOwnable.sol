// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/// @notice Interface shared by `Ownable` and `OwnableUpgradeable`.
///         https://eips.ethereum.org/EIPS/eip-173
/// @dev Interface selector: `0x0e083076`
interface IOwnable {
    ////////////////////////////////////////////////////////////////////////
    // Events
    ////////////////////////////////////////////////////////////////////////

    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);

    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    /// @notice The caller account is not authorized to perform an operation.
    /// @dev Error selector: `0x118cdaa7`
    error OwnableUnauthorizedAccount(address account);

    /// @notice The owner is not a valid owner account.
    /// @dev Error selector:  0x1e4fbdf7
    error OwnableInvalidOwner(address owner);

    ////////////////////////////////////////////////////////////////////////
    // Functions
    ////////////////////////////////////////////////////////////////////////

    /// @notice Transfers ownership of the contract to a new account.
    function transferOwnership(address newOwner) external;

    /// @notice Leaves the contract without owner.
    function renounceOwnership() external;

    /// @notice Returns the address of the current owner.
    function owner() external view returns (address);
}
