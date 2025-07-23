// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/common/BridgeEncoder.sol";
import {BridgeMessageType} from "../src/common/IBridge.sol";
import {TransferData, MigrationData} from "../src/common/TransferData.sol";
import {NameUtils} from "../src/common/NameUtils.sol";

// Wrapper contract to properly test library errors
contract BridgeEncoderWrapper {
    function decodeMigration(bytes memory message)
        external
        pure
        returns (bytes memory dnsEncodedName, MigrationData memory data)
    {
        return BridgeEncoder.decodeMigration(message);
    }

    function decodeEjection(bytes memory message)
        external
        pure
        returns (bytes memory dnsEncodedName, TransferData memory data)
    {
        return BridgeEncoder.decodeEjection(message);
    }
}

contract BridgeEncoderTest is Test {
    BridgeEncoderWrapper wrapper;

    function setUp() public {
        wrapper = new BridgeEncoderWrapper();
    }

    function testEncodeMigration() public view {
        TransferData memory transferData = TransferData({
            label: "test",
            owner: address(0x123),
            subregistry: address(0x456),
            resolver: address(0x789),
            expires: uint64(block.timestamp + 365 days),
            roleBitmap: 0x01
        });

        MigrationData memory migrationData =
            MigrationData({transferData: transferData, toL1: true, data: abi.encode("test data")});

        bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel("test");
        bytes memory encodedMessage = BridgeEncoder.encodeMigration(dnsEncodedName, migrationData);

        // Verify the message type is correct
        BridgeMessageType messageType = BridgeEncoder.getMessageType(encodedMessage);
        assertEq(uint256(messageType), uint256(BridgeMessageType.MIGRATION));

        // Verify we can decode the message back
        (bytes memory decodedDnsName, MigrationData memory decodedData) = BridgeEncoder.decodeMigration(encodedMessage);
        assertEq(decodedDnsName, dnsEncodedName);
        assertEq(decodedData.transferData.label, migrationData.transferData.label);
        assertEq(decodedData.transferData.owner, migrationData.transferData.owner);
        assertEq(decodedData.toL1, migrationData.toL1);
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
        assertEq(uint256(messageType), uint256(BridgeMessageType.EJECTION));

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

    function testDecodeMigrationInvalidMessageType() public {
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

        MigrationData memory migrationData =
            MigrationData({transferData: transferData, toL1: true, data: abi.encode("test data")});

        bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel("test");

        // Manually encode with wrong message type to test custom error
        bytes memory invalidMessage = abi.encode(uint256(BridgeMessageType.EJECTION), dnsEncodedName, migrationData);

        // Try to decode it as a migration message - should revert with custom error
        vm.expectRevert(abi.encodeWithSelector(BridgeEncoder.InvalidMigrationMessageType.selector));
        wrapper.decodeMigration(invalidMessage);
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
        bytes memory invalidMessage = abi.encode(uint256(BridgeMessageType.MIGRATION), dnsEncodedName, transferData);

        // Try to decode it as an ejection message - should revert with custom error
        vm.expectRevert(abi.encodeWithSelector(BridgeEncoder.InvalidEjectionMessageType.selector));
        wrapper.decodeEjection(invalidMessage);
    }

    function testDecodeIncompatibleStructures() public {
        // Test that trying to decode incompatible structures fails with ABI error
        TransferData memory transferData = TransferData({
            label: "test",
            owner: address(0x123),
            subregistry: address(0x456),
            resolver: address(0x789),
            expires: uint64(block.timestamp + 365 days),
            roleBitmap: 0x01
        });

        bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel("test");
        bytes memory ejectionMessage = BridgeEncoder.encodeEjection(dnsEncodedName, transferData);

        // Try to decode ejection message (TransferData) as migration message (MigrationData)
        // This should fail with generic revert due to ABI decoding mismatch
        vm.expectRevert();
        wrapper.decodeMigration(ejectionMessage);

        // Test the opposite: decode migration as ejection
        MigrationData memory migrationData =
            MigrationData({transferData: transferData, toL1: true, data: abi.encode("test data")});

        bytes memory migrationMessage = BridgeEncoder.encodeMigration(dnsEncodedName, migrationData);

        // This should also fail with generic revert due to ABI decoding mismatch
        vm.expectRevert();
        wrapper.decodeEjection(migrationMessage);
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
        assertEq(uint256(ejectionType), uint256(BridgeMessageType.EJECTION));

        // Test migration message type
        MigrationData memory migrationData =
            MigrationData({transferData: transferData, toL1: true, data: abi.encode("test data")});

        bytes memory migrationMessage = BridgeEncoder.encodeMigration(dnsEncodedName, migrationData);
        BridgeMessageType migrationType = BridgeEncoder.getMessageType(migrationMessage);
        assertEq(uint256(migrationType), uint256(BridgeMessageType.MIGRATION));
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

    function testMigrationDataEncoding() public view {
        // Test that migration data with complex nested data works
        TransferData memory transferData = TransferData({
            label: "complex",
            owner: address(0x111),
            subregistry: address(0x222),
            resolver: address(0x333),
            expires: uint64(block.timestamp + 1000 days),
            roleBitmap: 0x42
        });

        bytes memory complexData = abi.encode("complex migration data", uint256(12345), address(0x444));

        MigrationData memory migrationData = MigrationData({transferData: transferData, toL1: false, data: complexData});

        bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel("complex");
        bytes memory encodedMessage = BridgeEncoder.encodeMigration(dnsEncodedName, migrationData);

        // Decode and verify all fields including nested data
        (bytes memory decodedDnsName, MigrationData memory decodedData) = BridgeEncoder.decodeMigration(encodedMessage);

        assertEq(decodedDnsName, dnsEncodedName);
        assertEq(decodedData.transferData.label, migrationData.transferData.label);
        assertEq(decodedData.transferData.owner, migrationData.transferData.owner);
        assertEq(decodedData.toL1, migrationData.toL1);
        assertEq(decodedData.data, migrationData.data);

        // Decode the nested data to verify it's intact
        (string memory nestedString, uint256 nestedUint, address nestedAddress) =
            abi.decode(decodedData.data, (string, uint256, address));
        assertEq(nestedString, "complex migration data");
        assertEq(nestedUint, 12345);
        assertEq(nestedAddress, address(0x444));
    }
}
