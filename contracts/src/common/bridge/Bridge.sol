// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IBridge, BridgeMessageType} from "./interfaces/IBridge.sol";
import {ISurgeBridge, ISurgeBridgeMessageInvocable} from "./interfaces/ISurgeBridge.sol";
import {BridgeEncoderLib} from "./libraries/BridgeEncoderLib.sol";
import {TransferData} from "./types/TransferData.sol";

/**
 * @title Bridge
 * @notice Abstract base class for bridge contracts that integrate with Surge bridge
 * @dev Implements both sending messages via Surge and receiving messages through ISurgeBridgeMessageInvocable
 */
abstract contract Bridge is IBridge, ISurgeBridgeMessageInvocable {
    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    ISurgeBridge public immutable SURGE_BRIDGE;
    uint64 public immutable SOURCE_CHAIN_ID;
    uint64 public immutable DEST_CHAIN_ID;
    address public immutable BRIDGE_CONTROLLER;

    ////////////////////////////////////////////////////////////////////////
    // Events
    ////////////////////////////////////////////////////////////////////////

    event MessageSent(bytes message);
    event MessageReceived(bytes message);

    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    error OnlyBridgeController();
    error OnlySurgeBridge();
    error InsufficientFee(uint256 required, uint256 provided);

    ////////////////////////////////////////////////////////////////////////
    // Constructor
    ////////////////////////////////////////////////////////////////////////

    constructor(
        ISurgeBridge surgeBridge_,
        uint64 sourceChainId_,
        uint64 destChainId_,
        address bridgeController_
    ) {
        SURGE_BRIDGE = surgeBridge_;
        SOURCE_CHAIN_ID = sourceChainId_;
        DEST_CHAIN_ID = destChainId_;
        BRIDGE_CONTROLLER = bridgeController_;
    }

    ////////////////////////////////////////////////////////////////////////
    // IBridge Implementation
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Send a message to the destination chain via Surge bridge
     * @param message The encoded bridge message (ejection or renewal)
     */
    function sendMessage(bytes calldata message) external payable virtual override {
        emit MessageSent(message);

        // Calculate required gas limit based on message data length
        uint32 gasLimit = SURGE_BRIDGE.getMessageMinGasLimit(message.length);

        // Build Surge Message struct
        ISurgeBridge.Message memory surgeMessage = ISurgeBridge.Message({
            id: 0, // Auto-assigned by Surge bridge
            fee: uint64(msg.value), // Use provided ETH as fee
            gasLimit: gasLimit,
            from: address(0), // Auto-assigned by Surge bridge
            srcChainId: SOURCE_CHAIN_ID,
            srcOwner: msg.sender,
            destChainId: DEST_CHAIN_ID,
            destOwner: msg.sender,
            to: BRIDGE_CONTROLLER, // Target is the bridge controller on destination chain
            value: 0,
            data: message
        });

        // Send message through Surge bridge
        SURGE_BRIDGE.sendMessage{value: msg.value}(surgeMessage);
    }

    ////////////////////////////////////////////////////////////////////////
    // IMessageInvocable Implementation
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Receive and process a message from Surge bridge
     * @param _data The encoded bridge message data
     * @dev This is called by the Surge bridge on the destination chain
     */
    function onMessageInvocation(bytes calldata data) external payable virtual override {
        if (msg.sender != address(SURGE_BRIDGE)) {
            revert OnlySurgeBridge();
        }

        emit MessageReceived(data);

        // Decode message type and route to appropriate handler
        BridgeMessageType messageType = BridgeEncoderLib.getMessageType(data);

        if (messageType == BridgeMessageType.EJECTION) {
            TransferData memory transferData = BridgeEncoderLib.decodeEjection(data);
            _handleEjectionMessage(transferData.dnsEncodedName, transferData);
        } else if (messageType == BridgeMessageType.RENEWAL) {
            (uint256 tokenId, uint64 newExpiry) = BridgeEncoderLib.decodeRenewal(data);
            _handleRenewalMessage(tokenId, newExpiry);
        }
    }

    ////////////////////////////////////////////////////////////////////////
    // Abstract Methods
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Handle an ejection message
     * @param dnsEncodedName The DNS-encoded name being ejected
     * @param transferData The transfer data for the ejection
     * @dev Must be implemented by concrete bridge contracts (L1Bridge, L2Bridge)
     */
    function _handleEjectionMessage(
        bytes memory dnsEncodedName,
        TransferData memory transferData
    ) internal virtual;

    /**
     * @notice Handle a renewal message
     * @param tokenId The token ID being renewed
     * @param newExpiry The new expiry timestamp
     * @dev Must be implemented by concrete bridge contracts (L1Bridge, L2Bridge)
     */
    function _handleRenewalMessage(uint256 tokenId, uint64 newExpiry) internal virtual;
}
