// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {CCIPReader, OffchainLookup} from "@ens/contracts/ccipRead/CCIPReader.sol";

contract Coveralls is CCIPReader {
    function a() external view {}

    function b() external {}

    function c() external {
        ccipRead(address(this), abi.encodeCall(this.c2, ()));
    }

    function c2() external view {}

    function d() external {
        ccipRead(address(this), abi.encodeCall(this.d2, ()));
    }
    function d2() external view {
        string[] memory urls = new string[](1);
        urls[0] = 'data:application/json,{"data":"0x"}';
        revert OffchainLookup(address(this), urls, "", this.d3.selector, "");
    }
    function d3() external view {}
}
