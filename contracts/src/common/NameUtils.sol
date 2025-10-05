// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// TODO: fix @ens/contracts/utils/NameCoder.sol
import {NameCoder} from "./NameCoder.sol";
import {NameErrors} from "./NameErrors.sol";

library NameUtils {
    /// @dev The namehash of "eth".
    // Same as `keccak256(abi.encode(bytes32(0), keccak256("eth")))`.
    bytes32 constant ETH_NODE = 0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae;

    /// @dev The DNS-encoded name of "eth".
    //bytes constant ETH_NAME = "\x03eth\x00";

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

    function assertLabelSize(string memory label) internal pure returns (uint8) {
        uint256 n = bytes(label).length;
        if (n == 0) revert NameErrors.LabelIsEmpty();
        if (n > 255) revert NameErrors.LabelIsTooLong(label);
        return uint8(n);
    }

    function append(bytes memory name, string memory label) internal pure returns (bytes memory) {
        return abi.encodePacked(assertLabelSize(label), label, name);
    }

    // function equalityHash(bytes memory name, uint256 offset) internal pure returns (bytes32 hash) {
    //     if (offset >= name.length) {
    //         revert NameErrors.DNSDecodingFailed(name);
    //     }
    //     assembly {
    //         hash := keccak256(add(name, add(32, offset)), sub(mload(name), offset))
    //     }
    // }

    /// @dev DNS encodes a label as a .eth second-level domain.
    ///
    /// @param label The label to encode (e.g., "test" becomes "\x04test\x03eth\x00").
    ///
    /// @return The DNS-encoded name.
    function appendETH(string memory label) internal pure returns (bytes memory) {
        return append("\x03eth\x00", label);
    }

    /// @dev Extracts a label from a DNS-encoded name at the given offset.
    ///
    /// @param name The DNS-encoded name to extract from.
    /// @param offset The offset in the DNS-encoded name to start reading from.
    ///
    /// @return label The extracted label as a string.
    /// @return nextOffset The offset to the next label in the DNS-encoded name.
    function extractLabel(
        bytes memory name,
        uint256 offset
    ) internal pure returns (string memory label, uint256 nextOffset) {
        uint8 size;
        (size, nextOffset) = NameCoder.nextLabel(name, offset);
        label = new string(size);
        assembly {
            mcopy(add(label, 32), add(add(name, 33), offset), size)
        }
    }

    /// @dev Extracts the first label from a DNS-encoded name.
    ///
    /// @param name The DNS-encoded name to extract from.
    ///
    /// @return The extracted label as a string.
    function firstLabel(bytes memory name) internal pure returns (string memory) {
        (string memory label, ) = extractLabel(name, 0);
        if (bytes(label).length == 0) {
            revert NameErrors.LabelIsEmpty();
        }
        return label;
    }

    function isStopFree(string memory label) internal pure returns (bool ret) {
        assembly {
            function hasZeroByte(x) -> y {
                y := and(
                    and(
                        not(x),
                        sub(x, 0x0101010101010101010101010101010101010101010101010101010101010101)
                    ),
                    0x8080808080808080808080808080808080808080808080808080808080808080
                )
            }
            let ptr := add(label, 32)
            let end := add(ptr, mload(label))
            for {} lt(ptr, end) {} {
                let x := xor(
                    mload(ptr),
                    0x2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e
                )
                ptr := add(ptr, 32)
                if hasZeroByte(x) {
                    // check remaining bytes if last partial word
                    ret := 1
                    if gt(ptr, end) {
                        ret := iszero(hasZeroByte(shr(shl(3, sub(ptr, end)), x)))
                    }
                    break
                }
            }
        }
    }
}
