// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {AbstractUniversalResolver, NameCoder} from "./AbstractUniversalResolver.sol";
import {IRegistry} from "../registry/IRegistry.sol";
import {NameUtils} from "../utils/NameUtils.sol";

contract UniversalResolver is AbstractUniversalResolver {
    IRegistry public immutable rootRegistry;

    constructor(
        IRegistry root,
        string[] memory gateways
    ) AbstractUniversalResolver(msg.sender, gateways) {
        rootRegistry = root;
    }

    /// @dev Finds the resolver and registry responsible for `name`.
    /// @param name The name to find.
    /// @return registry The registry responsible for `name`.
    /// @return exact A boolean that is true if the registry is an exact match for `name`.
    /// @return resolver The resolver for `name`.
    /// @return offset The byte-offset into `name` of the name corresponding to the resolver.
    function _findResolver(
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
            return (rootRegistry, true, address(0), offset0);
        }
        (registry, exact, resolver, offset) = _findResolver(
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
            if (offset0 > 0) {
                IRegistry sub = registry.getSubregistry(label);
                if (address(sub) == address(0)) {
                    exact = false;
                } else {
                    registry = sub;
                }
            }
        }
    }

    function getRegistry(
        bytes memory name
    ) external view returns (IRegistry registry, bool exact) {
        (registry, exact, , ) = _findResolver(name, 0);
    }

    function findResolver(
        bytes memory name
    )
        public
        view
        override
        returns (address resolver, bytes32 node, uint256 offset)
    {
        node = NameCoder.namehash(name, 0); // confirms name is valid
        (, , resolver, offset) = _findResolver(name, 0);
    }
}
