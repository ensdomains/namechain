// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {AbstractUniversalResolver, NameCoder} from "./AbstractUniversalResolver.sol";
import {NameUtils} from "../common/NameUtils.sol";
import {IRegistry} from "../common/IRegistry.sol";

contract UniversalResolverV2 is AbstractUniversalResolver {
    IRegistry public immutable rootRegistry;

    constructor(IRegistry root, string[] memory gateways) AbstractUniversalResolver(msg.sender, gateways) {
        rootRegistry = root;
    }

    /// @inheritdoc AbstractUniversalResolver
    function findResolver(bytes memory name)
        public
        view
        override
        returns (address resolver, bytes32 node, uint256 offset)
    {
        node = NameCoder.namehash(name, 0); // check name
        (,, resolver, offset) = _findResolver(name, 0);
    }

    /// @dev Finds the resolver for `name`.
    /// @param name The name to find.
    /// @return registry The registry responsible for `name`.
    /// @return exact True if the registry is an exact match for `name`.
    /// @return resolver The resolver for `name`.
    /// @return offset The byte-offset into `name` of the name corresponding to the resolver.
    function _findResolver(bytes memory name, uint256 offset0)
        internal
        view
        returns (IRegistry registry, bool exact, address resolver, uint256 offset)
    {
        uint256 size = uint8(name[offset0]);
        if (size == 0) {
            return (rootRegistry, true, address(0), offset0);
        }
        (registry, exact, resolver, offset) = _findResolver(name, offset0 + 1 + size);
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

    /// @notice Finds the nearest registry for `name`.
    /// @param name The name to find.
    /// @return registry The nearest registry for `name`.
    /// @return exact True if the registry is an exact match for `name`.
    function getRegistry(bytes memory name) external view returns (IRegistry registry, bool exact) {
        (registry, exact,,) = _findResolver(name, 0);
    }

    /// @notice Finds the registry responsible for `name`.
    /// @param name The name to find.
    /// @return registry The registry responsible for `name` or null.
    /// @return label The leading label if `registry` exists or null.
    function getParentRegistry(bytes calldata name) external view returns (IRegistry registry, string memory label) {
        (bytes32 labelHash, uint256 offset) = NameCoder.readLabel(name, 0);
        if (labelHash != bytes32(0)) {
            (IRegistry parent, bool exact,,) = _findResolver(name, offset);
            if (exact) {
                registry = parent;
                label = string(name[1:offset]);
            }
        }
    }
}
