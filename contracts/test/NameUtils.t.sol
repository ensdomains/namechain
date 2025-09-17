// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/common/NameUtils.sol";

// Wrapper contract to properly test library functions
contract NameUtilsWrapper {
    function labelToCanonicalId(string memory label) external pure returns (uint256) {
        return NameUtils.labelToCanonicalId(label);
    }

    function getCanonicalId(uint256 id) external pure returns (uint256) {
        return NameUtils.getCanonicalId(id);
    }

    function dnsEncodeEthLabel(string memory label) external pure returns (bytes memory) {
        return NameUtils.dnsEncodeEthLabel(label);
    }

    function extractLabel(bytes memory dnsEncodedName, uint256 offset) 
        external 
        pure 
        returns (string memory label, uint256 nextOffset) 
    {
        return NameUtils.extractLabel(dnsEncodedName, offset);
    }

    function extractLabel(bytes memory dnsEncodedName) external pure returns (string memory) {
        return NameUtils.extractLabel(dnsEncodedName);
    }
}

contract NameUtilsTest is Test {
    NameUtilsWrapper wrapper;

    function setUp() public {
        wrapper = new NameUtilsWrapper();
    }

    // Test labelToCanonicalId function
    function test_labelToCanonicalId_BasicLabels() public {
        // Test common labels
        uint256 testId = wrapper.labelToCanonicalId("test");
        uint256 expectedHash = uint256(keccak256(bytes("test")));
        uint256 expected = expectedHash ^ uint32(expectedHash);
        assertEq(testId, expected);

        uint256 aliceId = wrapper.labelToCanonicalId("alice");
        expectedHash = uint256(keccak256(bytes("alice")));
        expected = expectedHash ^ uint32(expectedHash);
        assertEq(aliceId, expected);
    }

    function test_labelToCanonicalId_EmptyString() public {
        uint256 emptyId = wrapper.labelToCanonicalId("");
        uint256 expectedHash = uint256(keccak256(bytes("")));
        uint256 expected = expectedHash ^ uint32(expectedHash);
        assertEq(emptyId, expected);
    }

    function test_labelToCanonicalId_SpecialCharacters() public {
        uint256 specialId = wrapper.labelToCanonicalId("test-name_123");
        uint256 expectedHash = uint256(keccak256(bytes("test-name_123")));
        uint256 expected = expectedHash ^ uint32(expectedHash);
        assertEq(specialId, expected);
    }

    function test_labelToCanonicalId_UnicodeCharacters() public {
        uint256 unicodeId = wrapper.labelToCanonicalId(unicode"tëst");
        uint256 expectedHash = uint256(keccak256(bytes(unicode"tëst")));
        uint256 expected = expectedHash ^ uint32(expectedHash);
        assertEq(unicodeId, expected);
    }

    function testFuzz_labelToCanonicalId(string memory label) public {
        uint256 canonicalId = wrapper.labelToCanonicalId(label);
        uint256 expectedHash = uint256(keccak256(bytes(label)));
        uint256 expected = expectedHash ^ uint32(expectedHash);
        assertEq(canonicalId, expected);
    }

    // Test getCanonicalId function
    function test_getCanonicalId_BasicIds() public {
        uint256 id1 = 0x123456789abcdef0;
        uint256 canonical1 = wrapper.getCanonicalId(id1);
        uint256 expected1 = id1 ^ uint32(id1);
        assertEq(canonical1, expected1);

        uint256 id2 = 0xffffffffffffffff;
        uint256 canonical2 = wrapper.getCanonicalId(id2);
        uint256 expected2 = id2 ^ uint32(id2);
        assertEq(canonical2, expected2);
    }

    function test_getCanonicalId_ZeroId() public {
        uint256 canonical = wrapper.getCanonicalId(0);
        assertEq(canonical, 0);
    }

    function test_getCanonicalId_MaxId() public {
        uint256 maxId = type(uint256).max;
        uint256 canonical = wrapper.getCanonicalId(maxId);
        uint256 expected = maxId ^ uint32(maxId);
        assertEq(canonical, expected);
    }

    function test_getCanonicalId_Properties() public {
        uint256 id = 0x123456789abcdef0;
        uint256 canonical = wrapper.getCanonicalId(id);
        
        // Verify the canonical ID follows the expected formula: id ^ uint32(id)
        assertEq(canonical, id ^ uint32(id));
        
        // Test with a value where lower 32 bits are zero
        uint256 idZeroLower = 0x1234567800000000;
        uint256 canonicalZero = wrapper.getCanonicalId(idZeroLower);
        assertEq(canonicalZero, idZeroLower); // Should be unchanged since uint32(id) = 0
    }

    function testFuzz_getCanonicalId(uint256 id) public {
        uint256 canonical = wrapper.getCanonicalId(id);
        uint256 expected = id ^ uint32(id);
        assertEq(canonical, expected);
    }

    // Test dnsEncodeEthLabel function
    function test_dnsEncodeEthLabel_BasicLabels() public {
        bytes memory encoded = wrapper.dnsEncodeEthLabel("test");
        bytes memory expected = abi.encodePacked(
            bytes1(uint8(4)), // length of "test"
            "test",
            "\x03eth\x00"
        );
        assertEq(encoded, expected);
    }

    function test_dnsEncodeEthLabel_EmptyString() public {
        bytes memory encoded = wrapper.dnsEncodeEthLabel("");
        bytes memory expected = abi.encodePacked(
            bytes1(uint8(0)), // length of ""
            "",
            "\x03eth\x00"
        );
        assertEq(encoded, expected);
    }

    function test_dnsEncodeEthLabel_SingleCharacter() public {
        bytes memory encoded = wrapper.dnsEncodeEthLabel("a");
        bytes memory expected = abi.encodePacked(
            bytes1(uint8(1)), // length of "a"
            "a",
            "\x03eth\x00"
        );
        assertEq(encoded, expected);
    }

    function test_dnsEncodeEthLabel_LongLabel() public {
        string memory longLabel = "verylonglabelnamethatshouldstillwork";
        bytes memory encoded = wrapper.dnsEncodeEthLabel(longLabel);
        bytes memory expected = abi.encodePacked(
            bytes1(uint8(bytes(longLabel).length)),
            longLabel,
            "\x03eth\x00"
        );
        assertEq(encoded, expected);
    }

    function test_dnsEncodeEthLabel_SpecialCharacters() public {
        bytes memory encoded = wrapper.dnsEncodeEthLabel("test-name_123");
        bytes memory expected = abi.encodePacked(
            bytes1(uint8(13)), // length of "test-name_123"
            "test-name_123",
            "\x03eth\x00"
        );
        assertEq(encoded, expected);
    }

    function testFuzz_dnsEncodeEthLabel(string memory label) public {
        // Skip labels that are too long (DNS has 63 byte limit per label)
        vm.assume(bytes(label).length <= 63);
        
        bytes memory encoded = wrapper.dnsEncodeEthLabel(label);
        bytes memory expected = abi.encodePacked(
            bytes1(uint8(bytes(label).length)),
            label,
            "\x03eth\x00"
        );
        assertEq(encoded, expected);
    }

    // Test extractLabel function with offset
    function test_extractLabel_WithOffset_BasicCase() public {
        // Use the DNS encoding function to generate test input
        bytes memory dnsTestName = wrapper.dnsEncodeEthLabel("test");
        
        (string memory label, uint256 nextOffset) = wrapper.extractLabel(dnsTestName, 0);
        assertEq(label, "test");
        assertEq(nextOffset, 5); // 1 (length) + 4 (label) = 5
    }

    function test_extractLabel_WithOffset_SecondLabel() public {
        // Use the DNS encoding function to generate test input
        bytes memory dnsName = wrapper.dnsEncodeEthLabel("test");
        
        // Extract the second label (eth) from the DNS encoded name
        (string memory label, uint256 nextOffset) = wrapper.extractLabel(dnsName, 5);
        assertEq(label, "eth");
        assertEq(nextOffset, 9); // 5 + 1 (length) + 3 (label) = 9
    }


    function test_extractLabel_WithOffset_SingleCharLabel() public {
        // Use the DNS encoding function to generate single character test input
        bytes memory dnsSingleName = wrapper.dnsEncodeEthLabel("a");
        
        (string memory label, uint256 nextOffset) = wrapper.extractLabel(dnsSingleName, 0);
        assertEq(label, "a");
        assertEq(nextOffset, 2); // 1 (length) + 1 (label) = 2
    }

    // Test extractLabel function without offset (convenience function)
    function test_extractLabel_WithoutOffset_BasicCase() public {
        // Use the DNS encoding function to generate test input
        bytes memory dnsTestName = wrapper.dnsEncodeEthLabel("test");
        
        string memory label = wrapper.extractLabel(dnsTestName);
        assertEq(label, "test");
    }


    function test_extractLabel_WithoutOffset_SingleChar() public {
        // Use the DNS encoding function to generate single character test input
        bytes memory dnsSingleName = wrapper.dnsEncodeEthLabel("x");
        
        string memory label = wrapper.extractLabel(dnsSingleName);
        assertEq(label, "x");
    }

    // Integration tests combining multiple functions
    function test_integration_LabelToCanonicalIdAndBack() public {
        string memory originalLabel = "testlabel";
        uint256 canonicalId = wrapper.labelToCanonicalId(originalLabel);
        
        // Verify that the canonical ID is different from the raw hash
        uint256 rawHash = uint256(keccak256(bytes(originalLabel)));
        assertTrue(canonicalId != rawHash);
        
        // Verify the canonical ID follows the expected formula
        assertEq(canonicalId, rawHash ^ uint32(rawHash));
    }

    function test_integration_DnsEncodeAndExtract() public {
        string memory originalLabel = "mytest";
        bytes memory encoded = wrapper.dnsEncodeEthLabel(originalLabel);
        string memory extracted = wrapper.extractLabel(encoded);
        
        assertEq(extracted, originalLabel);
    }

    function test_integration_MultipleLabelsExtraction() public {
        // Use the DNS encoding function to generate test input
        bytes memory dnsName = wrapper.dnsEncodeEthLabel("alice");
        
        // Extract first label
        (string memory label1, uint256 offset1) = wrapper.extractLabel(dnsName, 0);
        assertEq(label1, "alice");
        
        // Extract second label (eth) from the DNS encoded name
        (string memory label2, ) = wrapper.extractLabel(dnsName, offset1);
        assertEq(label2, "eth");
    }

    // Edge cases and error conditions
    function test_edge_MaxLengthLabel() public {
        // Create a 63-byte label (max DNS label length)
        string memory maxLabel = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijk";
        require(bytes(maxLabel).length == 63, "Test setup error");
        
        uint256 canonicalId = wrapper.labelToCanonicalId(maxLabel);
        uint256 expectedHash = uint256(keccak256(bytes(maxLabel)));
        assertEq(canonicalId, expectedHash ^ uint32(expectedHash));
        
        bytes memory encoded = wrapper.dnsEncodeEthLabel(maxLabel);
        string memory extracted = wrapper.extractLabel(encoded);
        assertEq(extracted, maxLabel);
    }

    function test_edge_CanonicalIdConsistency() public {
        // Test that the same input always produces the same canonical ID
        string memory label = "consistency";
        uint256 id1 = wrapper.labelToCanonicalId(label);
        uint256 id2 = wrapper.labelToCanonicalId(label);
        assertEq(id1, id2);
        
        uint256 canonical1 = wrapper.getCanonicalId(12345);
        uint256 canonical2 = wrapper.getCanonicalId(12345);
        assertEq(canonical1, canonical2);
    }

    function test_edge_DifferentLabelsProduceDifferentIds() public {
        uint256 id1 = wrapper.labelToCanonicalId("test1");
        uint256 id2 = wrapper.labelToCanonicalId("test2");
        assertTrue(id1 != id2);
    }
}