// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

/// @dev Convenience functions for names.
contract NameMixin {
    function namehash(bytes memory name) internal pure returns (bytes32) {
        return NameCoder.namehash(name, 0);
    }

    function firstLabel(bytes memory name) internal pure returns (string memory) {
        return NameCoder.firstLabel(name);
    }

    function firstTokenId(bytes memory name) internal pure returns (uint256) {
        return uint256(keccak256(bytes(firstLabel(name))));
    }
}
