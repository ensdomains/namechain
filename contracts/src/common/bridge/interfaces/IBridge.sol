// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @dev Interface for the bridge contract.
 */
interface IBridge {
    function sendMessage(bytes memory message) external;
}
