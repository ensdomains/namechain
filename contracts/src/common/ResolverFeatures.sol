// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

library ResolverFeatures {
    /// @notice Implements `resolve(multicall([...]))`.
    /// @dev Feature: `0xcc086793a6ab`
    bytes6 constant RESOLVE_MULTICALL =
        bytes6(keccak256("ens.resolver.extended.multicall"));

    /// @notice Returns the same records independent of name or node.
    /// @dev Feature: `0xd45afd822f9c`
    bytes6 constant DEDICATED = bytes6(keccak256("ens.resolver.dedicated"));
}
