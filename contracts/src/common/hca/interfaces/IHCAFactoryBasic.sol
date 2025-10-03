// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @dev Basic interface for the HCA factory.
interface IHCAFactoryBasic {
    /// @notice Returns the account owner of the given HCA
    /// @param hca The HCA to get the account owner of
    /// @return The account owner of the given HCA
    function getAccountOwner(address hca) external view returns (address);
}
