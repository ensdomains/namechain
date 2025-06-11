// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

library ResolverFeatures {
    /// @notice Implements `resolve(multicall([...]))`.
    /// @dev Feature: `0xcc086793a6ab`
    bytes6 constant RESOLVE_MULTICALL =
        bytes6(keccak256("ens.resolver.extended.multicall"));

    /// @notice Returns the same records independent of name or node.
    /// @dev Feature: `0xfaa33450d7bc`
    bytes6 constant SINGULAR = bytes6(keccak256("ens.resolver.singular"));
}
