// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {TransferData, MigrationData} from "./TransferData.sol";


/**
 * @dev Interface for the bridge contract.
 */
interface IBridge {
    function sendMessage(bytes memory message) external;
}


/**
 * @dev The type of message being sent.
 */
enum BridgeMessageType {
    EJECTION,
    RENEWAL
}

/**
 * @dev Library containing bridge-related role definitions
 */
library LibBridgeRoles {
    uint256 internal constant ROLE_EJECTOR = 1 << 0;
    uint256 internal constant ROLE_EJECTOR_ADMIN = ROLE_EJECTOR << 128;
}


