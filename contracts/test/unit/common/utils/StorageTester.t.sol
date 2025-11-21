// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";

import {StorageTester} from "./StorageTester.sol";

contract StorageTesterTest is StorageTester {
    bytes smallData;
    bytes bigData;
    mapping(bytes => bytes) mappedData;

    function setUp() external {
        smallData = vm.randomBytes(31);
        bigData = vm.randomBytes(99);
        mappedData["small"] = smallData;
        mappedData["big"] = bigData;
    }

    function test_readBytes_smallData() external view {
        uint256 slot;
        assembly {
            slot := smallData.slot
        }
        assertEq(readBytes(address(this), slot), smallData);
    }

    function test_readBytes_bigData() external view {
        uint256 slot;
        assembly {
            slot := bigData.slot
        }
        assertEq(readBytes(address(this), slot), bigData);
    }

    function test_mapped_readBytes_smallData() external view {
        uint256 slot;
        assembly {
            slot := mappedData.slot
        }
        assertEq(readBytes(address(this), follow(slot, "small")), smallData);
    }

    function test_mapped_readBytes_bigData() external view {
        uint256 slot;
        assembly {
            slot := mappedData.slot
        }
        assertEq(readBytes(address(this), follow(slot, "big")), bigData);
    }
}
