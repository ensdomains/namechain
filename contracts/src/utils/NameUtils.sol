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
     * @dev Converts a label to a token ID.
     * @param label The label to convert.
     * @return tokenId The token ID corresponding to this label.
     */
    function labelToTokenId(string memory label) internal pure returns (uint256) {
        return uint256(keccak256(bytes(label)));
    }       
}
