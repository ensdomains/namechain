// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IExtendedResolver} from "@ens/contracts/resolvers/profiles/IExtendedResolver.sol";

/// @notice Interface for a wildcard resolver that supports `resolve(multicall)`.
/// @dev Interface selector: `0xf904bb79`
interface IExtendedResolverWithMulticall is IExtendedResolver {
    /// @dev Dummy function to populate the interface.
    function __IExtendedResolverWithMulticall() external pure;
}
