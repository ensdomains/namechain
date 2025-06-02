// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {TransferData} from "../common/EjectionController.sol";

interface IBridge {
    function sendMessageToL1(uint256 tokenId, TransferData memory transferData) external;
    function sendMessageToL2(uint256 tokenId, TransferData memory transferData) external;
}