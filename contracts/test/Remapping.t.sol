// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test, console} from "forge-std/Test.sol";

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

contract TestRemapping is Test {
    function encode(string memory ens) external pure {
        NameCoder.encode(ens);
    }

    function test_encode_noHashed() external {
        vm.expectRevert();
        this.encode(new string(256));
    }

    function readLabel(bytes memory name) external pure returns (bytes32 labelHash) {
        (labelHash, ) = NameCoder.readLabel(name, 0);
    }

    function test_readLabel_ignoresHashed() external view {
        assertNotEq(
            this.readLabel(
                NameCoder.encode(
                    "[1111111111111111111111111111111111111111111111111111111111111111]"
                )
            ),
            0x1111111111111111111111111111111111111111111111111111111111111111
        );
    }

    function test_readLabel_allowsNullHashed() external view {
        assertNotEq(
            this.readLabel(
                NameCoder.encode(
                    "[0000000000000000000000000000000000000000000000000000000000000000]"
                )
            ),
            bytes32(0)
        );
    }

    function test_a() external {
        console.logBytes(NameCoder.encode("raffy.eth"));
        console.logBytes(NameCoder.encode("eth"));
    }
}
