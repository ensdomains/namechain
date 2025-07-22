// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

library TestUtils {
    uint256 public constant ALL_ROLES = 0x1111111111111111111111111111111111111111111111111111111111111111;

    function toAddressArray(address a, address b) internal pure returns (address[] memory) {
        address[] memory arr = new address[](2);
        arr[0] = a;
        arr[1] = b;
        return arr;
    }

    function toUint8Array(uint8 a, uint8 b) internal pure returns (uint8[] memory) {
        uint8[] memory arr = new uint8[](2);
        arr[0] = a;
        arr[1] = b;
        return arr;
    }
}
