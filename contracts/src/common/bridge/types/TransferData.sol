// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IRegistry} from "../../registry/interfaces/IRegistry.sol";

uint256 constant TRANSFER_DATA_MIN_SIZE = 96 + 5 * 32;

struct TransferData {
    string label;
    uint64 expiry;
    address owner;
    IRegistry subregistry;
    address resolver;
    uint256 roleBitmap;
}
