// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

library NameUtils {
    /// @dev Read a label at an offset from a DNS-encoded name.
    ///      eg. `readLabel("\x03abc\x00", 0) = "abc"`.
    /// @param name The name.
    /// @param pos The offset of the label.
    /// @return label The label.
    function readLabel(
        bytes memory name,
        uint256 pos
    ) internal pure returns (string memory label) {
        uint256 len = uint8(name[pos]);
        label = new string(len);
        assembly {
            mcopy(add(label, 32), add(add(name, 33), pos), len)
        }
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
}
