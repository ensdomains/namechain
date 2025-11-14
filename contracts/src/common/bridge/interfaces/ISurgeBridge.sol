// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ISurgeBridge
/// @notice Subset of Surge protocol's IBridge interface with modifications to facilitate bridge calls
/// @dev This interface includes only the essential methods and types needed for ENS bridging.
///      It extends Surge's IBridge with a helper method for gas limit calculation.
/// @custom:security-contact security@taiko.xyz
interface ISurgeBridge {
    struct Message {
        // Message ID whose value is automatically assigned.
        uint64 id;
        // The max processing fee for the relayer.
        uint64 fee;
        // gasLimit that the processMessage call must have.
        uint32 gasLimit;
        // The address, EOA or contract, that interacts with this bridge.
        address from;
        // Source chain ID whose value is automatically assigned.
        uint64 srcChainId;
        // The owner of the message on the source chain.
        address srcOwner;
        // Destination chain ID where the `to` address lives.
        uint64 destChainId;
        // The owner of the message on the destination chain.
        address destOwner;
        // The destination address on the destination chain.
        address to;
        // value to invoke on the destination chain.
        uint256 value;
        // callData to invoke on the destination chain.
        bytes data;
    }

    /// @notice Emitted when a message is sent.
    /// @param msgHash The hash of the message.
    /// @param message The message.
    event MessageSent(bytes32 indexed msgHash, Message message);

    /// @notice Sends a message to the destination chain and takes custody
    /// of Ether required in this contract.
    /// @param message The message to be sent.
    /// @return msgHash_ The hash of the sent message.
    /// @return message_ The updated message sent.
    function sendMessage(
        Message calldata message
    ) external payable returns (bytes32 msgHash_, Message memory message_);

    /// @notice Get the minimum gas limit required for a message
    /// @param dataLength The length of the message data
    /// @return The minimum gas limit
    function getMessageMinGasLimit(uint256 dataLength) external pure returns (uint32);
}

/// @title ISurgeBridgeMessageInvocable
/// @notice Clone of Surge protocol's IMessageInvocable interface
/// @dev This interface must be implemented by contracts that receive bridge messages
interface ISurgeBridgeMessageInvocable {
    /// @notice Called when this contract is the bridge target.
    /// @param data The data for this contract to interpret.
    /// @dev This method should be guarded with `onlyFromNamed("bridge")`.
    function onMessageInvocation(bytes calldata data) external payable;
}
