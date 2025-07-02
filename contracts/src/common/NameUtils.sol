// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {HexUtils} from "@ens/contracts/utils/HexUtils.sol";

library NameUtils {
    /// @dev Determine if label is a hashed label.
    ///      Matches: `/^\[[0-9a-f]{64}\]$/i`.
    /// @param label The label to check.
    /// @return hashed True if the label is a hashed label.
    function isHashedLabel(
        string memory label
    ) internal pure returns (bool hashed) {
        if (
            bytes(label).length == 66 &&
            bytes(label)[0] == "[" &&
            bytes(label)[65] == "]"
        ) {
            (, hashed) = HexUtils.hexStringToBytes32(bytes(label), 1, 65);
        }
    }

    /// @dev Determine if label is a valid length and not a hashed label.
    /// @param label The label to check.
    /// @return True if the label is valid.
    function isValidLabel(string memory label) internal pure returns (bool) {
        return
            bytes(label).length > 0 &&
            bytes(label).length <= 255 &&
            !isHashedLabel(label);
    }

    /// @dev Convert a label to canonical id.
    /// @param label The label to convert.
    /// @return The canonical id corresponding to this label.
    function labelToCanonicalId(
        string memory label
    ) internal pure returns (uint256) {
        return getCanonicalId(uint256(keccak256(bytes(label))));
    }

    /// @dev Get the canonical id of a token id or canonical id.
    /// @param id The token id or canonical id to convert to its canonical id version.
    /// @return The canonical id.
    function getCanonicalId(uint256 id) internal pure returns (uint256) {
        return id ^ uint32(id);
    }

    /// @dev DNS encodes a label as a .eth second-level domain.
    /// @param label The label to encode (e.g., "test" becomes "\x04test\x03eth\x00").
    /// @return The DNS-encoded name.
    function dnsEncodeEthLabel(
        string memory label
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                bytes1(uint8(bytes(label).length)),
                label,
                "\x03eth\x00"
            );
    }
}
