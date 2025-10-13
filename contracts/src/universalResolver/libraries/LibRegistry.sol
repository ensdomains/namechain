// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

import {IRegistry} from "../../common/registry/interfaces/IRegistry.sol";

library LibRegistry {
    /// @dev Find the resolver address for `name[offset:]`.
    ///
    /// @param rootRegistry The root ENS registry.
    /// @param name The DNS-encoded name to search.
    /// @param offset The offset into `name` to begin the search.
    ///
    /// @return exactRegistry The exact registry or null if not exact.
    /// @return resolver The resolver or null if not found.
    /// @return node The namehash of `name[offset:]`.
    /// @return resolverOffset The offset into `name` corresponding to `resolver`.
    function findResolver(
        IRegistry rootRegistry,
        bytes memory name,
        uint256 offset
    )
        internal
        view
        returns (IRegistry exactRegistry, address resolver, bytes32 node, uint256 resolverOffset)
    {
        // supply <root> if end of name
        (bytes32 labelHash, uint256 next) = NameCoder.readLabel(name, offset);
        if (labelHash == bytes32(0)) {
            return (rootRegistry, address(0), bytes32(0), offset);
        }
        // lookup parent name
        (exactRegistry, resolver, node, resolverOffset) = findResolver(rootRegistry, name, next);
        // if there was a parent registry...
        if (address(exactRegistry) != address(0)) {
            (string memory label, ) = NameCoder.extractLabel(name, offset);
            // remember the resolver (if it exists)
            address res = exactRegistry.getResolver(label);
            if (res != address(0)) {
                resolver = res;
                resolverOffset = offset;
            }
            exactRegistry = exactRegistry.getSubregistry(label);
        }
        node = NameCoder.namehash(node, labelHash); // update namehash
    }

    /// @dev Find the exact registry for `name[offset:]`.
    ///
    /// @param rootRegistry The root ENS registry.
    /// @param name The DNS-encoded name to search.
    ///
    /// @return exactRegistry The exact registry or null if not found.
    function findExactRegistry(
        IRegistry rootRegistry,
        bytes memory name,
        uint256 offset
    ) internal view returns (IRegistry exactRegistry) {
        (bytes32 labelHash, uint256 next) = NameCoder.readLabel(name, offset);
        if (labelHash == bytes32(0)) {
            return rootRegistry;
        }
        IRegistry parent = findExactRegistry(rootRegistry, name, next);
        if (address(parent) != address(0)) {
            (string memory label, ) = NameCoder.extractLabel(name, offset);
            exactRegistry = parent.getSubregistry(label);
        }
    }

    /// @dev Find the parent registry for `name[offset:]`.
    ///
    /// @param rootRegistry The root ENS registry.
    /// @param name The DNS-encoded name to search.
    ///
    /// @return parentRegistry The parent registry or null if not found.
    function findParentRegistry(
        IRegistry rootRegistry,
        bytes memory name,
        uint256 offset
    ) internal view returns (IRegistry parentRegistry) {
        (bytes32 labelHash, uint256 next) = NameCoder.readLabel(name, offset);
        if (labelHash != bytes32(0)) {
            parentRegistry = findExactRegistry(rootRegistry, name, next);
        }
    }
}
