// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";

import {PreimageDatastore, IPreimageDatastore, LabelHashPreimage} from "../src/registry/PreimageDatastore.sol";

contract TestPreimageDatastore is Test {
    IPreimageDatastore datastore;

    function setUp() public {
        datastore = new PreimageDatastore();
    }

    function testFuzz_label(string memory label) public {
        datastore.setLabel(label);
        string memory saved = datastore.label(uint256(keccak256(bytes(label))));
        assertEq(keccak256(bytes(saved)), keccak256(bytes(label)));
    }
}
