// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/common/BridgeEncoder.sol";
import {BridgeMessageType} from "../src/common/IBridge.sol";
import {TransferData} from "../src/common/TransferData.sol";
import {NameUtils} from "../src/common/NameUtils.sol";

// Wrapper contract to properly test library errors
contract BridgeEncoderWrapper {
    function decodeEjection(bytes memory message) external pure returns (
        bytes memory dnsEncodedName,
        TransferData memory data
    ) {
        return BridgeEncoder.decodeEjection(message);
    }

    function decodeRenewal(bytes memory message) external pure returns (
        uint256 tokenId,
        uint64 newExpiry
    ) {
        return BridgeEncoder.decodeRenewal(message);
    }
}

contract BridgeEncoderTest is Test {
    BridgeEncoderWrapper wrapper;

    function setUp() public {
        wrapper = new BridgeEncoderWrapper();
    }

    function testEncodeEjection() public view {
        TransferData memory transferData = TransferData({
            label: "test",
            owner: address(0x123),
            subregistry: address(0x456),
            resolver: address(0x789),
            expires: uint64(block.timestamp + 365 days),
            roleBitmap: 0x01
        });

        bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel("test");
        bytes memory encodedMessage = BridgeEncoder.encodeEjection(dnsEncodedName, transferData);
        
        // Verify the message type is correct
        BridgeMessageType messageType = BridgeEncoder.getMessageType(encodedMessage);
        assertEq(uint(messageType), uint(BridgeMessageType.EJECTION));
        
        // Verify we can decode the message back
        (bytes memory decodedDnsName, TransferData memory decodedData) = BridgeEncoder.decodeEjection(encodedMessage);
        assertEq(decodedDnsName, dnsEncodedName);
        assertEq(decodedData.label, transferData.label);
        assertEq(decodedData.owner, transferData.owner);
        assertEq(decodedData.subregistry, transferData.subregistry);
        assertEq(decodedData.resolver, transferData.resolver);
        assertEq(decodedData.expires, transferData.expires);
        assertEq(decodedData.roleBitmap, transferData.roleBitmap);
    }

    function testEncodeRenewal() public view {
        uint256 tokenId = 12345;
        uint64 newExpiry = uint64(block.timestamp + 365 days);

        bytes memory encodedMessage = BridgeEncoder.encodeRenewal(tokenId, newExpiry);
        
        // Verify the message type is correct
        BridgeMessageType messageType = BridgeEncoder.getMessageType(encodedMessage);
        assertEq(uint(messageType), uint(BridgeMessageType.RENEWAL));
        
        // Verify we can decode the message back
        (uint256 decodedTokenId, uint64 decodedExpiry) = BridgeEncoder.decodeRenewal(encodedMessage);
        assertEq(decodedTokenId, tokenId);
        assertEq(decodedExpiry, newExpiry);
    }

    function testDecodeEjectionInvalidMessageType() public {
        // Create a message with wrong message type but correct structure
        // to test the custom error (not ABI decoding error)
        TransferData memory transferData = TransferData({
            label: "test",
            owner: address(0x123),
            subregistry: address(0x456),
            resolver: address(0x789),
            expires: uint64(block.timestamp + 365 days),
            roleBitmap: 0x01
        });

        bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel("test");
        
        // Manually encode with wrong message type to test custom error
        bytes memory invalidMessage = abi.encode(uint(BridgeMessageType.RENEWAL), dnsEncodedName, transferData);
        
        // Try to decode it as an ejection message - should revert with custom error
        vm.expectRevert(abi.encodeWithSelector(BridgeEncoder.InvalidEjectionMessageType.selector));
        wrapper.decodeEjection(invalidMessage);
    }

    function testDecodeRenewalInvalidMessageType() public {
        uint256 tokenId = 12345;
        uint64 newExpiry = uint64(block.timestamp + 365 days);
        
        // Manually encode with wrong message type to test custom error
        bytes memory invalidMessage = abi.encode(uint(BridgeMessageType.EJECTION), tokenId, newExpiry);
        
        // Try to decode it as a renewal message - should revert with custom error
        vm.expectRevert(abi.encodeWithSelector(BridgeEncoder.InvalidRenewalMessageType.selector));
        wrapper.decodeRenewal(invalidMessage);
    }

    function testGetMessageType() public view {
        TransferData memory transferData = TransferData({
            label: "test",
            owner: address(0x123),
            subregistry: address(0x456),
            resolver: address(0x789),
            expires: uint64(block.timestamp + 365 days),
            roleBitmap: 0x01
        });

        bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel("test");
        
        // Test ejection message type
        bytes memory ejectionMessage = BridgeEncoder.encodeEjection(dnsEncodedName, transferData);
        BridgeMessageType ejectionType = BridgeEncoder.getMessageType(ejectionMessage);
        assertEq(uint(ejectionType), uint(BridgeMessageType.EJECTION));
        
        // Test renewal message type
        uint256 tokenId = 12345;
        uint64 newExpiry = uint64(block.timestamp + 365 days);
        bytes memory renewalMessage = BridgeEncoder.encodeRenewal(tokenId, newExpiry);
        BridgeMessageType renewalType = BridgeEncoder.getMessageType(renewalMessage);
        assertEq(uint(renewalType), uint(BridgeMessageType.RENEWAL));
    }

    function testEncodingStructure() public view {
        // Test that the new encoding structure works correctly
        TransferData memory transferData = TransferData({
            label: "structuretest",
            owner: address(0x999),
            subregistry: address(0x888),
            resolver: address(0x777),
            expires: uint64(block.timestamp + 500 days),
            roleBitmap: 0xFF
        });

        bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel("structuretest");
        bytes memory encodedMessage = BridgeEncoder.encodeEjection(dnsEncodedName, transferData);
        
        // Decode and verify all fields match exactly
        (bytes memory decodedDnsName, TransferData memory decodedData) = BridgeEncoder.decodeEjection(encodedMessage);
        
        assertEq(decodedDnsName, dnsEncodedName);
        assertEq(decodedData.label, transferData.label);
        assertEq(decodedData.owner, transferData.owner);
        assertEq(decodedData.subregistry, transferData.subregistry);
        assertEq(decodedData.resolver, transferData.resolver);
        assertEq(decodedData.expires, transferData.expires);
        assertEq(decodedData.roleBitmap, transferData.roleBitmap);
    }
} 