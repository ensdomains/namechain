// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ENS} from "@ens/contracts/registry/ENS.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

library ResolverFinderV1 {
    /// @dev Efficiently find the resolver address for `name[offset:]`.
    /// @param registry The ENS registry.
    /// @param name The name to search.
    /// @param offset The byte-offset into `name` to begin the search.
    /// @return resolver The address of the resolver.
    /// @return node The namehash of name corresponding to the resolver.
    /// @return offset_ The byte-offset into `name` of the name corresponding to the resolver.
    function findResolver(
        ENS registry,
        bytes memory name,
        uint256 offset
    ) internal view returns (address resolver, bytes32 node, uint256 offset_) {
        (bytes32 labelHash, uint256 next) = NameCoder.readLabel(name, offset);
        if (labelHash != bytes32(0)) {
            (
                address parentResolver,
                bytes32 parentNode,
                uint256 parentOffset
            ) = findResolver(registry, name, next);
            assembly {
                mstore(0, parentNode)
                mstore(32, labelHash)
                node := keccak256(0, 64) // compute namehash()
            }
            resolver = registry.resolver(node);
            return
                resolver != address(0)
                    ? (resolver, node, offset)
                    : (parentResolver, node, parentOffset);
        }
    }
}
