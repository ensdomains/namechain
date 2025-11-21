// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";

contract StorageTester is Test {
    /// @dev Read storage `bytes` from `addr` @ `slot`.
    function readBytes(address addr, uint256 slot) public view returns (bytes memory v) {
        uint256 first = uint256(vm.load(addr, bytes32(slot)));
        if ((first & 1) == 0) {
            uint256 size = (first & 255) >> 1;
            vm.assertLt(size, 32, "small too big");
            v = abi.encodePacked(first);
            assembly {
                mstore(v, size) // truncate
            }
        } else {
            uint256 size = first >> 1;
            vm.assertGe(size, 32, "big too small");
            v = new bytes(size);
            size = (size + 31) >> 5; // words
            slot = uint256(keccak256(abi.encode(slot)));
            for (uint256 i; i < size; ++i) {
                bytes32 word = vm.load(addr, bytes32(slot + i));
                assembly {
                    mstore(add(v, shl(5, add(i, 1))), word)
                }
            }
        }
    }

    /// @dev Compute slot for `mapping[key]` where `slot = mapping.slot`.
    function follow(uint256 slot, bytes memory key) public pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(key, slot)));
    }
}
