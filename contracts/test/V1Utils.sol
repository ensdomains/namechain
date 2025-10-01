// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

library LibV1 {
    bytes32 constant ETH_NODE =
        keccak256(abi.encode(bytes32(0), keccak256("eth")));

    function getUnwrappedTokenId(
        string memory label
    ) internal pure returns (uint256) {
        return uint256(keccak256(bytes(label)));
    }
    function getWrappedTokenId(uint256 id) internal pure returns (uint256) {
        return uint256(NameCoder.namehash(ETH_NODE, bytes32(id)));
    }
    function getWrappedTokenId(
        string memory label
    ) internal pure returns (uint256) {
        return getWrappedTokenId(getWrappedTokenId(label));
    }
}
