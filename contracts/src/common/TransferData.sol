// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

/**
 * @dev The data for inter-chain transfers of a name.
 */
struct TransferData {
    bytes name;
    address owner;
    address subregistry;
    address resolver;
    uint256 roleBitmap;
    uint64 expiry;
}
