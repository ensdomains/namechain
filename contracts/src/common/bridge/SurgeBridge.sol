// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {EnhancedAccessControl} from "../access-control/EnhancedAccessControl.sol";

import {IBridge, BridgeMessageType} from "./interfaces/IBridge.sol";
import {
    ISurgeNativeBridge,
    ISurgeNativeBridgeMessageInvocable
} from "./interfaces/ISurgeNativeBridge.sol";
import {BridgeEncoderLib} from "./libraries/BridgeEncoderLib.sol";
import {TransferData} from "./types/TransferData.sol";

/**
 * @title SurgeBridge
 * @notice Abstract base class for bridge contracts that integrate with Surge bridge
 * @dev Implements both sending messages via Surge and receiving messages through ISurgeNativeBridgeMessageInvocable
 */
abstract contract SurgeBridge is
    IBridge,
    ISurgeNativeBridgeMessageInvocable,
    EnhancedAccessControl
{
    ////////////////////////////////////////////////////////////////////////
    // Role Constants
    ////////////////////////////////////////////////////////////////////////

    uint256 public constant ROLE_BRIDGE_MANAGER = 1 << 0;
    uint256 public constant ROLE_BRIDGE_MANAGER_ADMIN = ROLE_BRIDGE_MANAGER << 128;

    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    uint64 public immutable SOURCE_CHAIN_ID;
    uint64 public immutable DEST_CHAIN_ID;
    address public immutable BRIDGE_CONTROLLER;

    ISurgeNativeBridge public surgeNativeBridge;
    address public destBridgeAddress;

    ////////////////////////////////////////////////////////////////////////
    // Events
    ////////////////////////////////////////////////////////////////////////

    event MessageSent(bytes message);
    event MessageReceived(bytes message);
    event SurgeNativeBridgeUpdated(ISurgeNativeBridge oldBridge, ISurgeNativeBridge newBridge);
    event DestBridgeAddressUpdated(address oldAddress, address newAddress);

    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    error OnlyBridgeController();
    error OnlySurgeNativeBridge();
    error InsufficientFee(uint256 required, uint256 provided);
    error DestBridgeAddressNotSet();

    ////////////////////////////////////////////////////////////////////////
    // Modifiers
    ////////////////////////////////////////////////////////////////////////

    modifier onlyBridgeController() {
        if (msg.sender != BRIDGE_CONTROLLER) {
            revert OnlyBridgeController();
        }
        _;
    }

    ////////////////////////////////////////////////////////////////////////
    // Constructor
    ////////////////////////////////////////////////////////////////////////

    constructor(
        ISurgeNativeBridge surgeNativeBridge_,
        uint64 sourceChainId_,
        uint64 destChainId_,
        address bridgeController_
    ) {
        surgeNativeBridge = surgeNativeBridge_;
        SOURCE_CHAIN_ID = sourceChainId_;
        DEST_CHAIN_ID = destChainId_;
        BRIDGE_CONTROLLER = bridgeController_;

        // Grant bridge manager admin role to deployer
        _grantRoles(ROOT_RESOURCE, ROLE_BRIDGE_MANAGER_ADMIN, msg.sender, true);
    }

    ////////////////////////////////////////////////////////////////////////
    // Admin Functions
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Set the Surge native bridge address
     * @param newSurgeNativeBridge The new Surge native bridge address
     */
    function setSurgeNativeBridge(
        ISurgeNativeBridge newSurgeNativeBridge
    ) external onlyRoles(ROOT_RESOURCE, ROLE_BRIDGE_MANAGER_ADMIN) {
        ISurgeNativeBridge oldBridge = surgeNativeBridge;
        surgeNativeBridge = newSurgeNativeBridge;

        emit SurgeNativeBridgeUpdated(oldBridge, newSurgeNativeBridge);
    }

    /**
     * @notice Set the destination bridge address
     * @param newDestBridgeAddress The new destination bridge address
     */
    function setDestBridgeAddress(
        address newDestBridgeAddress
    ) external onlyRoles(ROOT_RESOURCE, ROLE_BRIDGE_MANAGER_ADMIN) {
        address oldAddress = destBridgeAddress;
        destBridgeAddress = newDestBridgeAddress;

        emit DestBridgeAddressUpdated(oldAddress, newDestBridgeAddress);
    }

    ////////////////////////////////////////////////////////////////////////
    // IBridge Implementation
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Send a message to the destination chain via Surge bridge
     * @param message The encoded bridge message (ejection or renewal)
     */
    function sendMessage(
        bytes calldata message
    ) external payable virtual override onlyBridgeController {
        if (destBridgeAddress == address(0)) {
            revert DestBridgeAddressNotSet();
        }

        // Calculate required gas limit based on message data length
        uint32 gasLimit = surgeNativeBridge.getMessageMinGasLimit(message.length);

        // Build Surge Message struct
        ISurgeNativeBridge.Message memory surgeMessage = ISurgeNativeBridge.Message({
            id: 0, // Auto-assigned by Surge bridge
            fee: uint64(msg.value), // Use provided ETH as fee
            gasLimit: gasLimit,
            from: address(0), // Auto-assigned by Surge bridge
            srcChainId: SOURCE_CHAIN_ID,
            srcOwner: msg.sender,
            destChainId: DEST_CHAIN_ID,
            destOwner: msg.sender,
            to: destBridgeAddress, // Target is the bridge on destination chain
            value: 0,
            data: message
        });

        // Send message through Surge bridge
        surgeNativeBridge.sendMessage{value: msg.value}(surgeMessage);

        emit MessageSent(message);
    }

    ////////////////////////////////////////////////////////////////////////
    // IMessageInvocable Implementation
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Receive and process a message from Surge bridge
     * @param data The encoded bridge message data
     * @dev This is called by the Surge bridge on the destination chain
     */
    function onMessageInvocation(bytes calldata data) external payable virtual override {
        if (msg.sender != address(surgeNativeBridge)) {
            revert OnlySurgeNativeBridge();
        }

        // Decode message type and route to appropriate handler
        BridgeMessageType messageType = BridgeEncoderLib.getMessageType(data);

        if (messageType == BridgeMessageType.EJECTION) {
            TransferData memory transferData = BridgeEncoderLib.decodeEjection(data);
            _handleEjectionMessage(transferData.dnsEncodedName, transferData);
        } else if (messageType == BridgeMessageType.RENEWAL) {
            (uint256 tokenId, uint64 newExpiry) = BridgeEncoderLib.decodeRenewal(data);
            _handleRenewalMessage(tokenId, newExpiry);
        }

        emit MessageReceived(data);
    }

    /**
     * @notice Get the minimum gas limit required for sending a message
     * @param message The message bytes to calculate gas limit for
     * @return The minimum gas limit
     */
    function getMinGasLimit(
        bytes calldata message
    ) external view virtual override returns (uint32) {
        return surgeNativeBridge.getMessageMinGasLimit(message.length);
    }

    ////////////////////////////////////////////////////////////////////////
    // Abstract Methods
    ////////////////////////////////////////////////////////////////////////

    /**
     * @notice Handle an ejection message
     * @param dnsEncodedName The DNS-encoded name being ejected
     * @param transferData The transfer data for the ejection
     * @dev Must be implemented by concrete bridge contracts (L1SurgeBridge, L2SurgeBridge)
     */
    function _handleEjectionMessage(
        bytes memory dnsEncodedName,
        TransferData memory transferData
    ) internal virtual;

    /**
     * @notice Handle a renewal message
     * @param tokenId The token ID being renewed
     * @param newExpiry The new expiry timestamp
     * @dev Must be implemented by concrete bridge contracts (L1SurgeBridge, L2SurgeBridge)
     */
    function _handleRenewalMessage(uint256 tokenId, uint64 newExpiry) internal virtual;
}
