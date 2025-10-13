// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IExtendedResolver} from "@ens/contracts/resolvers/profiles/IExtendedResolver.sol";

interface ICompositeExtendedResolver is IExtendedResolver {
    /// @notice Fetch the underlying resolver for `name`.
    ///         Callers should enable EIP-3668.
    ///
    /// @param name The DNS-encoded name.
    ///
    /// @return resolver The underlying resolver address.
    /// @return offchain `true` if required offchain data.
    function getResolver(bytes memory name) external view returns (address resolver, bool offchain);

    /// @notice Determine if resolving `name` requires offchain data.
    ///
    /// @param name The DNS-encoded name.
    ///
    /// @return `true` if requires offchain data.
    function isResolverOffchain(bytes calldata name) external view returns (bool);
}
