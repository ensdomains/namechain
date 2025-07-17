// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IRegistry} from "../common/IRegistry.sol";
import {NameUtils} from "../common/NameUtils.sol";

library ResolverFinder {
    /// @dev The DNS-encoded name is malformed.
    ///      Error selector: `0xba4adc23`
    ///      See: NameCoder.sol
    error DNSDecodingFailed(bytes dns);

    /// @dev Finds the resolver for `name`.
    /// @param registry The root ENS registry.
    /// @param name The name to find.
    /// @return registry The registry responsible for `name`.
    /// @return exact True if the registry is an exact match for `name`.
    /// @return resolver The resolver for `name`.
    /// @return offset The byte-offset into `name` of the name corresponding to the resolver.
    function findResolver(
        IRegistry rootRegistry,
        bytes memory name,
        uint256 offset0
    )
        internal
        view
        returns (
            IRegistry registry,
            bool exact,
            address resolver,
            uint256 offset
        )
    {
        uint256 size = uint8(name[offset0]);
        if (size == 0) {
            if (offset0 + 1 != name.length) {
                revert DNSDecodingFailed(name); // junk at end
            }
            return (rootRegistry, true, address(0), offset0);
        }
        (registry, exact, resolver, offset) = findResolver(
            rootRegistry,
            name,
            offset0 + 1 + size
        );
        if (exact) {
            string memory label = NameUtils.readLabel(name, offset0);
            address r = registry.getResolver(label);
            if (r != address(0)) {
                resolver = r;
                offset = offset0;
            }
            IRegistry sub = registry.getSubregistry(label);
            if (address(sub) == address(0)) {
                exact = false;
            } else {
                registry = sub;
            }
        }
    }
}
