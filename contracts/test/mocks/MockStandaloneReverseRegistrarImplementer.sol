// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// solhint-disable no-empty-blocks, namechain/ordering

import {
    StandaloneReverseRegistrar
} from "~src/common/reverse-registrar/StandaloneReverseRegistrar.sol";

contract MockStandaloneReverseRegistrarImplementer is StandaloneReverseRegistrar {
    constructor(string memory label) StandaloneReverseRegistrar(label) {}

    // Test helper functions
    function setName(address addr, string calldata name_) public {
        _setName(addr, name_);
    }

    function toAddressString(address value) public pure returns (string memory) {
        return _toAddressString(value);
    }

    function SIMPLE_HASHED_PARENT() public view returns (bytes32) {
        return _SIMPLE_HASHED_PARENT;
    }

    function PARENT_LENGTH() public view returns (uint256) {
        return _PARENT_LENGTH;
    }
}
