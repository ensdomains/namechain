// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IBridge {
    function sendMessageToL1(bytes calldata message) external;
    function sendMessageToL2(bytes calldata message) external;
}