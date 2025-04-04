// File: mocks/MockL1Bridge.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IController {
    function processMessage(bytes calldata message) external;
}
