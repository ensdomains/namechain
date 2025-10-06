// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

import {NameUtils} from "../../src/common/NameUtils.sol";

contract NameMixin {
    function namehash(bytes memory name) internal pure returns (bytes32) {
        return NameCoder.namehash(name, 0);
    }

    function firstLabel(bytes memory name) internal pure returns (string memory) {
        return NameUtils.firstLabel(name);
    }

    function dotEthToken(bytes memory name) internal pure returns (uint256 tokenId) {
        (bytes32 labelHash, uint256 offset) = NameCoder.readLabel(name, 0);
        require(NameCoder.namehash(name, offset) == NameUtils.ETH_NODE, "not .eth");
        return uint256(labelHash);
    }
}
