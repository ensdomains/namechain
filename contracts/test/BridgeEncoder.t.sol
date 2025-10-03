// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering, one-contract-per-file

import {Test} from "forge-std/Test.sol";

import {BridgeEncoder} from "./../src/common/BridgeEncoder.sol";
import {BridgeMessageType} from "./../src/common/IBridge.sol";
import {NameUtils} from "./../src/common/NameUtils.sol";
import {TransferData} from "./../src/common/TransferData.sol";

// Wrapper contract to properly test library errors
contract BridgeEncoderWrapper {
    function decodeEjection(bytes memory message) external pure returns (TransferData memory data) {
        return BridgeEncoder.decodeEjection(message);
    }

    function decodeRenewal(
        bytes memory message
    ) external pure returns (uint256 tokenId, uint64 newExpiry) {
        return BridgeEncoder.decodeRenewal(message);
    }
}

contract BridgeEncoderTest is Test {
    BridgeEncoderWrapper wrapper;

    function setUp() public {
        wrapper = new BridgeEncoderWrapper();
    }

    function testEncodeEjection() public view {
        bytes memory name = NameUtils.appendETH("test");
        TransferData memory transferData = TransferData({
            name: name,
            owner: address(0x123),
            subregistry: address(0x456),
            resolver: address(0x789),
            expiry: uint64(block.timestamp + 365 days),
            roleBitmap: 0x01
        });

        bytes memory encodedMessage = BridgeEncoder.encodeEjection(transferData);

        // Verify the message type is correct
        BridgeMessageType messageType = BridgeEncoder.getMessageType(encodedMessage);
        assertEq(uint256(messageType), uint256(BridgeMessageType.EJECTION));

        // Verify we can decode the message back
        (TransferData memory decodedData) = BridgeEncoder.decodeEjection(encodedMessage);
        assertEq(keccak256(decodedData.name), keccak256(name));
        assertEq(keccak256(decodedData.name), keccak256(transferData.name));
        assertEq(decodedData.owner, transferData.owner);
        assertEq(decodedData.subregistry, transferData.subregistry);
        assertEq(decodedData.resolver, transferData.resolver);
        assertEq(decodedData.expiry, transferData.expiry);
        assertEq(decodedData.roleBitmap, transferData.roleBitmap);
    }

    function testEncodeRenewal() public view {
        uint256 tokenId = 12345;
        uint64 newExpiry = uint64(block.timestamp + 365 days);

        bytes memory encodedMessage = BridgeEncoder.encodeRenewal(tokenId, newExpiry);

        // Verify the message type is correct
        BridgeMessageType messageType = BridgeEncoder.getMessageType(encodedMessage);
        assertEq(uint256(messageType), uint256(BridgeMessageType.RENEWAL));

        // Verify we can decode the message back
        (uint256 decodedTokenId, uint64 decodedExpiry) = BridgeEncoder.decodeRenewal(
            encodedMessage
        );
        assertEq(decodedTokenId, tokenId);
        assertEq(decodedExpiry, newExpiry);
    }

    function testDecodeEjectionInvalidMessageType() public {
        // Create a message with wrong message type but correct structure
        // to test the custom error (not ABI decoding error)
        bytes memory name = NameUtils.appendETH("test");
        TransferData memory transferData = TransferData({
            name: name,
            owner: address(0x123),
            subregistry: address(0x456),
            resolver: address(0x789),
            expiry: uint64(block.timestamp + 365 days),
            roleBitmap: 0x01
        });

        // Manually encode with wrong message type to test custom error
        bytes memory invalidMessage = abi.encode(uint256(BridgeMessageType.RENEWAL), transferData);

        // Try to decode it as an ejection message - should revert with custom error
        vm.expectRevert(abi.encodeWithSelector(BridgeEncoder.InvalidEjectionMessageType.selector));
        wrapper.decodeEjection(invalidMessage);
    }

    function testDecodeRenewalInvalidMessageType() public {
        uint256 tokenId = 12345;
        uint64 newExpiry = uint64(block.timestamp + 365 days);

        // Manually encode with wrong message type to test custom error
        bytes memory invalidMessage = abi.encode(
            uint256(BridgeMessageType.EJECTION),
            tokenId,
            newExpiry
        );

        // Try to decode it as a renewal message - should revert with custom error
        vm.expectRevert(abi.encodeWithSelector(BridgeEncoder.InvalidRenewalMessageType.selector));
        wrapper.decodeRenewal(invalidMessage);
    }

    function testGetMessageType() public view {
        bytes memory name = NameUtils.appendETH("test");
        TransferData memory transferData = TransferData({
            name: name,
            owner: address(0x123),
            subregistry: address(0x456),
            resolver: address(0x789),
            expiry: uint64(block.timestamp + 365 days),
            roleBitmap: 0x01
        });

        // Test ejection message type
        bytes memory ejectionMessage = BridgeEncoder.encodeEjection(transferData);
        BridgeMessageType ejectionType = BridgeEncoder.getMessageType(ejectionMessage);
        assertEq(uint256(ejectionType), uint256(BridgeMessageType.EJECTION));

        // Test renewal message type
        uint256 tokenId = 12345;
        uint64 newExpiry = uint64(block.timestamp + 365 days);
        bytes memory renewalMessage = BridgeEncoder.encodeRenewal(tokenId, newExpiry);
        BridgeMessageType renewalType = BridgeEncoder.getMessageType(renewalMessage);
        assertEq(uint256(renewalType), uint256(BridgeMessageType.RENEWAL));
    }

    function testEncodingStructure() public view {
        // Test that the new encoding structure works correctly
        bytes memory name = NameUtils.appendETH("structuretest");
        TransferData memory transferData = TransferData({
            name: name,
            owner: address(0x999),
            subregistry: address(0x888),
            resolver: address(0x777),
            expiry: uint64(block.timestamp + 500 days),
            roleBitmap: 0xFF
        });

        bytes memory encodedMessage = BridgeEncoder.encodeEjection(transferData);

        // Decode and verify all fields match exactly
        (TransferData memory decodedData) = BridgeEncoder.decodeEjection(encodedMessage);

        assertEq(keccak256(decodedData.name), keccak256(name));
        assertEq(keccak256(decodedData.name), keccak256(transferData.name));
        assertEq(decodedData.owner, transferData.owner);
        assertEq(decodedData.subregistry, transferData.subregistry);
        assertEq(decodedData.resolver, transferData.resolver);
        assertEq(decodedData.expiry, transferData.expiry);
        assertEq(decodedData.roleBitmap, transferData.roleBitmap);
    }
}
