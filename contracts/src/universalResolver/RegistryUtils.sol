// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

import {IRegistry} from "../common/IRegistry.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

library RegistryUtils {
    /// @dev Find the resolver address for `name[offset:]`.
    /// @param rootRegistry The root ENS registry.
    /// @param name The DNS-encoded name to search.
    /// @param offset The offset into `name` to begin the search.
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
        returns (
            IRegistry exactRegistry,
            address resolver,
            bytes32 node,
            uint256 resolverOffset
        )
    {
        // supply <root> if end of name
        (bytes32 labelHash, uint256 next) = NameCoder.readLabel(name, offset);
        if (labelHash == bytes32(0)) {
            return (rootRegistry, address(0), bytes32(0), offset);
        }
        // lookup parent name
        (exactRegistry, resolver, node, resolverOffset) = findResolver(
            rootRegistry,
            name,
            next
        );
        // if there was a parent registry...
        if (address(exactRegistry) != address(0)) {
            string memory label = readLabel(name, offset);
            // remember the resolver (if it exists)
            address res = exactRegistry.getResolver(label);
            if (res != address(0)) {
                resolver = res;
                resolverOffset = offset;
            }
            exactRegistry = exactRegistry.getSubregistry(label);
        }
        // update namehash
        node = keccak256(abi.encode(node, labelHash));
    }

    /// @dev Find the exact registry for `name[offset:]`.
    /// @param rootRegistry The root ENS registry.
    /// @param name The DNS-encoded name to search.
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
            string memory label = readLabel(name, offset);
            exactRegistry = parent.getSubregistry(label);
        }
    }

    /// @dev Find the parent registry for `name[offset:]`.
    /// @param rootRegistry The root ENS registry.
    /// @param name The DNS-encoded name to search.
    /// @return parentRegistry The parent registry or null if not found.
    function findParentRegistry(
        IRegistry rootRegistry,
        bytes calldata name,
        uint256 offset
    ) external view returns (IRegistry parentRegistry) {
        (bytes32 labelHash, uint256 next) = NameCoder.readLabel(name, offset);
        if (labelHash != bytes32(0)) {
            parentRegistry = findExactRegistry(rootRegistry, name, next);
        }
    }

    /// @dev Read label at offset from a DNS-encoded name.
    ///      eg. `readLabel("\x03abc\x00", 0) = "abc"`.
    /// @param name The DNS-encoded name.
    /// @param offset The offset into `name`
    /// @return label The label.
    function readLabel(
        bytes memory name,
        uint256 offset
    ) internal pure returns (string memory label) {
        (uint8 size, ) = nextLabel(name, offset);
        label = new string(size);
        assembly {
            mcopy(add(label, 32), add(add(name, 33), offset), size)
        }
    }

    // ********************************************************************************
    // I'd like to move the following code here:
    // https://github.com/ensdomains/ens-contracts/pull/459
    // https://github.com/ensdomains/ens-contracts/blob/fix/namecoder-iter/contracts/utils/NameCoder.sol#L42
    // ********************************************************************************

    /// @dev Read the `size` of the label at `offset`.
    ///      If `size = 0`, it must be the end of `name` (no junk at end).
    ///      Reverts `DNSDecodingFailed`.
    /// @param name The DNS-encoded name.
    /// @param offset The offset into `name` to start reading.
    /// @return size The size of the label in bytes.
    /// @return nextOffset The offset into `name` of the next label.
    function nextLabel(
        bytes memory name,
        uint256 offset
    ) internal pure returns (uint8 size, uint256 nextOffset) {
        assembly {
            size := byte(0, mload(add(add(name, 32), offset))) // uint8(name[offset])
            nextOffset := add(offset, add(1, size)) // offset + 1 + size
        }
        if (size > 0 ? nextOffset >= name.length : nextOffset != name.length) {
            revert NameCoder.DNSDecodingFailed(name);
        }
    }
}
