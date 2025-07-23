// SPDX-License-Identifier: MIT
pragma solidity ~0.8.13;

library NameUtils {
    function readLabel(bytes memory name, uint256 idx) internal view returns (string memory label) {
        uint256 len = uint8(name[idx]);
        label = new string(len);
        assembly {
            // Use the identity precompile to copy memory
            pop(staticcall(gas(), 4, add(add(name, 33), idx), len, add(label, 32), len))
        }
    }

    /**
     * @dev Converts a label to a canonical id.
     * @param label The label to convert.
     * @return canonicalId The canonical id corresponding to this label.
     */
    function labelToCanonicalId(string memory label) internal pure returns (uint256) {
        return getCanonicalId(uint256(keccak256(bytes(label))));
    }

    /**
     * @dev Gets the canonical id version of a token id or canonical id.
     * @param id The token id or canonical id to convert to its canonical id version.
     * @return canonicalId The canonical id.
     */
    function getCanonicalId(uint256 id) internal pure returns (uint256) {
        return id & 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000;
    }

    /**
     * @dev DNS encodes a label as a .eth second-level domain.
     * @param label The label to encode (e.g., "test" becomes "\x04test\x03eth\x00").
     * @return The DNS-encoded name.
     */
    function dnsEncodeEthLabel(string memory label) internal pure returns (bytes memory) {
        return abi.encodePacked(bytes1(uint8(bytes(label).length)), label, "\x03eth\x00");
    }
}
