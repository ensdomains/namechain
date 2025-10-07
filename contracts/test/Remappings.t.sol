// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test, console} from "forge-std/Test.sol";

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

/// @dev Ensure remappings.txt is applied correctly.
///
/// Note: Forge does not recompile changes to file remappings as expected.
/// You must induce a recompile via clean or file change.
///
/// 1. (Temporary) Check NameCoder is remapped while removing hashing.
/// 2. Check LibCopy is remapped to get `mcopy`.
///
contract RemappingsTest is Test {
    function _encode(string memory ens) external pure {
        NameCoder.encode(ens);
    }

    function test_encode_noHashed() external {
        vm.expectRevert();
        this._encode(new string(256));
    }

    function _readLabel(bytes memory name) external pure returns (bytes32 labelHash) {
        (labelHash, ) = NameCoder.readLabel(name, 0);
    }

    function test_readLabel_ignoresHashed() external view {
        assertNotEq(
            this._readLabel(
                NameCoder.encode(
                    "[1111111111111111111111111111111111111111111111111111111111111111]"
                )
            ),
            0x1111111111111111111111111111111111111111111111111111111111111111
        );
    }

    function test_readLabel_allowsNullHashed() external view {
        assertNotEq(
            this._readLabel(
                NameCoder.encode(
                    "[0000000000000000000000000000000000000000000000000000000000000000]"
                )
            ),
            bytes32(0)
        );
    }
}
