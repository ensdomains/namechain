// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

library NameUtils {
    // TODO: move to NameCoder
    error NameContainsHashedLabel(bytes name);

    /// @notice Same as `Namcoder.namehash()` but reverts if any label is hashed.
    function unhashedNamehash(
        bytes memory name,
        uint256 offset
    ) internal pure returns (bytes32 hash) {
        bool wasHashed;
        (hash, offset, , wasHashed) = NameCoder.readLabel(name, offset, true);
        if (wasHashed) {
            revert NameContainsHashedLabel(name);
        }
        if (hash != bytes32(0)) {
            hash = NameCoder.namehash(unhashedNamehash(name, offset), hash);
        }
    }

    /// @dev Convert a label to canonical id.
    ///
    /// @param label The label to convert.
    ///
    /// @return The canonical id corresponding to this label.
    function labelToCanonicalId(string memory label) internal pure returns (uint256) {
        return getCanonicalId(uint256(keccak256(bytes(label))));
    }

    /// @dev Get the canonical id of a token id or canonical id.
    ///
    /// @param id The token id or canonical id to convert to its canonical id version.
    ///
    /// @return The canonical id.
    function getCanonicalId(uint256 id) internal pure returns (uint256) {
        return id ^ uint32(id);
    }

    function appendLabel(
        bytes memory name,
        string memory label
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(bytes(label).length), label, name);
    }

    /// @dev DNS encodes a label as a .eth second-level domain.
    ///
    /// @param label The label to encode (e.g., "test" becomes "\x04test\x03eth\x00").
    ///
    /// @return The DNS-encoded name.
    function dnsEncodeEthLabel(string memory label) internal pure returns (bytes memory) {
        return appendLabel("\x03eth\x00", label);
    }

    /// @dev Extracts a label from a DNS-encoded name at the given offset.
    ///
    /// @param dnsEncodedName The DNS-encoded name to extract from.
    /// @param offset The offset in the DNS-encoded name to start reading from.
    ///
    /// @return label The extracted label as a string.
    /// @return nextOffset The offset to the next label in the DNS-encoded name.
    function extractLabel(
        bytes memory dnsEncodedName,
        uint256 offset
    ) internal pure returns (string memory label, uint256 nextOffset) {
        (, uint256 _nextOffset, uint8 size, ) = NameCoder.readLabel(dnsEncodedName, offset, false);
        nextOffset = _nextOffset;
        label = new string(size);
        assembly {
            mcopy(add(label, 32), add(add(dnsEncodedName, 33), offset), size)
        }
    }

    /// @dev Extracts the first label from a DNS-encoded name.
    ///
    /// @param dnsEncodedName The DNS-encoded name to extract from.
    ///
    /// @return The extracted label as a string.
    function extractLabel(bytes memory dnsEncodedName) internal pure returns (string memory) {
        (string memory label, ) = extractLabel(dnsEncodedName, 0);
        return label;
    }
}
