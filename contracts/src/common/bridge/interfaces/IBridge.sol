// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @dev The type of message being sent.
 */
enum BridgeMessageType {
    EJECTION,
    RENEWAL
}

/**
 * @dev Interface for the bridge contract.
 */
interface IBridge {
    function sendMessage(bytes memory message) external payable;
    function getMinGasLimit(bytes calldata message) external view returns (uint32);
}
