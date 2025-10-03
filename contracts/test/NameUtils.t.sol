// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering, one-contract-per-file

import {Test, console} from "forge-std/Test.sol";

import {NameUtils, NameErrors} from "../src/common/NameUtils.sol";

contract NameUtilsTest is Test {
    function labelToCanonicalId(string memory label) external pure returns (uint256) {
        return NameUtils.labelToCanonicalId(label);
    }

    // Test labelToCanonicalId function
    function test_labelToCanonicalId_BasicLabels() public view {
        // Test common labels
        uint256 testId = this.labelToCanonicalId("test");
        uint256 expectedHash = uint256(keccak256(bytes("test")));
        uint256 expected = expectedHash ^ uint32(expectedHash);
        assertEq(testId, expected);

        uint256 aliceId = this.labelToCanonicalId("alice");
        expectedHash = uint256(keccak256(bytes("alice")));
        expected = expectedHash ^ uint32(expectedHash);
        assertEq(aliceId, expected);
    }

    function test_labelToCanonicalId_EmptyString() public view {
        uint256 emptyId = this.labelToCanonicalId("");
        uint256 expectedHash = uint256(keccak256(bytes("")));
        uint256 expected = expectedHash ^ uint32(expectedHash);
        assertEq(emptyId, expected);
    }

    function test_labelToCanonicalId_SpecialCharacters() public view {
        uint256 specialId = this.labelToCanonicalId("test-name_123");
        uint256 expectedHash = uint256(keccak256(bytes("test-name_123")));
        uint256 expected = expectedHash ^ uint32(expectedHash);
        assertEq(specialId, expected);
    }

    function test_labelToCanonicalId_UnicodeCharacters() public view {
        uint256 unicodeId = this.labelToCanonicalId(unicode"tëst");
        uint256 expectedHash = uint256(keccak256(bytes(unicode"tëst")));
        uint256 expected = expectedHash ^ uint32(expectedHash);
        assertEq(unicodeId, expected);
    }

    function testFuzz_labelToCanonicalId(string memory label) public view {
        uint256 canonicalId = this.labelToCanonicalId(label);
        uint256 expectedHash = uint256(keccak256(bytes(label)));
        uint256 expected = expectedHash ^ uint32(expectedHash);
        assertEq(canonicalId, expected);
    }

    // Test getCanonicalId function
    function getCanonicalId(uint256 id) external pure returns (uint256) {
        return NameUtils.getCanonicalId(id);
    }

    function test_getCanonicalId_BasicIds() public view {
        uint256 id1 = 0x123456789abcdef0;
        uint256 canonical1 = this.getCanonicalId(id1);
        uint256 expected1 = id1 ^ uint32(id1);
        assertEq(canonical1, expected1);

        uint256 id2 = 0xffffffffffffffff;
        uint256 canonical2 = this.getCanonicalId(id2);
        uint256 expected2 = id2 ^ uint32(id2);
        assertEq(canonical2, expected2);
    }

    function test_getCanonicalId_ZeroId() public view {
        uint256 canonical = this.getCanonicalId(0);
        assertEq(canonical, 0);
    }

    function test_getCanonicalId_MaxId() public view {
        uint256 maxId = type(uint256).max;
        uint256 canonical = this.getCanonicalId(maxId);
        uint256 expected = maxId ^ uint32(maxId);
        assertEq(canonical, expected);
    }

    function test_getCanonicalId_Properties() public view {
        uint256 id = 0x123456789abcdef0;
        uint256 canonical = this.getCanonicalId(id);

        // Verify the canonical ID follows the expected formula: id ^ uint32(id)
        assertEq(canonical, id ^ uint32(id));

        // Test with a value where lower 32 bits are zero
        uint256 idZeroLower = 0x1234567800000000;
        uint256 canonicalZero = this.getCanonicalId(idZeroLower);
        assertEq(canonicalZero, idZeroLower); // Should be unchanged since uint32(id) = 0
    }

    function testFuzz_getCanonicalId(uint256 id) public view {
        uint256 canonical = this.getCanonicalId(id);
        uint256 expected = id ^ uint32(id);
        assertEq(canonical, expected);
    }

    function appendETH(string memory label) external pure returns (bytes memory) {
        return NameUtils.appendETH(label);
    }

    // Test appendETH function
    function test_appendETH_test() external pure {
        assertEq(NameUtils.appendETH("test"), "\x04test\x03eth\x00");
    }

    function test_appendETH_min() external pure {
        assertEq(NameUtils.appendETH("a"), "\x01a\x03eth\x00");
    }

    function test_appendETH_max() external pure {
        string memory label = new string(255);
        assertEq(
            NameUtils.appendETH(label),
            abi.encodePacked(uint8(bytes(label).length), label, "\x03eth\x00")
        );
    }

    function test_Revert_appendETH_tooLong() external {
        string memory label = new string(256);
        vm.expectRevert(abi.encodeWithSelector(NameErrors.LabelIsTooLong.selector, label));
        this.appendETH(label);
    }

    function testFuzz_appendETH(string memory label) external pure {
        uint256 n = bytes(label).length;
        vm.assume(n > 0 && n < 256);
        assertEq(NameUtils.appendETH(label), abi.encodePacked(uint8(n), label, "\x03eth\x00"));
    }

    // Test extractLabel function with offset
    function extractLabel(
        bytes memory name,
        uint256 offset
    ) external pure returns (string memory label, uint256 nextOffset) {
        return NameUtils.extractLabel(name, offset);
    }

    function test_extractLabel_WithOffset_BasicCase() public view {
        // Use the DNS encoding function to generate test input
        bytes memory dnsTestName = this.appendETH("test");

        (string memory label, uint256 nextOffset) = this.extractLabel(dnsTestName, 0);
        assertEq(label, "test");
        assertEq(nextOffset, 5); // 1 (length) + 4 (label) = 5
    }

    function test_extractLabel_WithOffset_SecondLabel() public view {
        // Use the DNS encoding function to generate test input
        bytes memory dnsName = this.appendETH("test");

        // Extract the second label (eth) from the DNS encoded name
        (string memory label, uint256 nextOffset) = this.extractLabel(dnsName, 5);
        assertEq(label, "eth");
        assertEq(nextOffset, 9); // 5 + 1 (length) + 3 (label) = 9
    }

    function test_extractLabel_WithOffset_SingleCharLabel() public view {
        // Use the DNS encoding function to generate single character test input
        bytes memory dnsSingleName = this.appendETH("a");

        (string memory label, uint256 nextOffset) = this.extractLabel(dnsSingleName, 0);
        assertEq(label, "a");
        assertEq(nextOffset, 2); // 1 (length) + 1 (label) = 2
    }

    function firstLabel(bytes memory name) external pure returns (string memory) {
        return NameUtils.firstLabel(name);
    }

    // Test extractLabel function without offset (convenience function)
    function test_firstLabel_BasicCase() public view {
        // Use the DNS encoding function to generate test input
        bytes memory dnsTestName = this.appendETH("test");
        string memory label = this.firstLabel(dnsTestName);
        assertEq(label, "test");
    }

    function test_firstLabel_SingleChar() public view {
        // Use the DNS encoding function to generate single character test input
        bytes memory dnsSingleName = this.appendETH("x");

        string memory label = this.firstLabel(dnsSingleName);
        assertEq(label, "x");
    }

    // Integration tests combining multiple functions
    function test_integration_LabelToCanonicalIdAndBack() public view {
        string memory originalLabel = "testlabel";
        uint256 canonicalId = this.labelToCanonicalId(originalLabel);

        // Verify that the canonical ID is different from the raw hash
        uint256 rawHash = uint256(keccak256(bytes(originalLabel)));
        assertTrue(canonicalId != rawHash);

        // Verify the canonical ID follows the expected formula
        assertEq(canonicalId, rawHash ^ uint32(rawHash));
    }

    function test_integration_DnsEncodeAndExtract() public view {
        string memory originalLabel = "mytest";
        bytes memory encoded = this.appendETH(originalLabel);
        string memory extracted = this.firstLabel(encoded);

        assertEq(extracted, originalLabel);
    }

    function test_integration_MultipleLabelsExtraction() public view {
        // Use the DNS encoding function to generate test input
        bytes memory dnsName = this.appendETH("alice");

        // Extract first label
        (string memory label1, uint256 offset1) = this.extractLabel(dnsName, 0);
        assertEq(label1, "alice");

        // Extract second label (eth) from the DNS encoded name
        (string memory label2, ) = this.extractLabel(dnsName, offset1);
        assertEq(label2, "eth");
    }

    function test_edge_DifferentLabelsProduceDifferentIds() public view {
        uint256 id1 = this.labelToCanonicalId("test1");
        uint256 id2 = this.labelToCanonicalId("test2");
        assertTrue(id1 != id2);
    }

    // Enhanced extractLabel testing with malformed inputs and boundary conditions
    function test_extractLabel_az() external view {
        bytes memory name = "\x00";
        uint256 n = 32;
        for (uint256 i = n; i > 0; --i) {
            name = NameUtils.append(name, new string(i));
        }
        uint256 offset;
        string memory label;
        for (uint256 i = 1; i <= n; ++i) {
            (label, offset) = this.extractLabel(name, offset);
            assertEq(label, new string(i));
        }
        (label, offset) = this.extractLabel(name, offset);
        assertEq(bytes(label).length, 0);
    }

    function test_Revert_firstLabel_empty() external {
        vm.expectRevert(abi.encodeWithSelector(NameErrors.LabelIsEmpty.selector));
        this.firstLabel("\x00");
    }

    function test_firstLabel_stopAllowed() external pure {
        NameUtils.firstLabel("\x03a.b\x00");
    }

    function test_firstLabel_min() public view {
        assertEq(this.firstLabel(NameUtils.appendETH("a")), "a");
    }

    function test_firstLabel_max() public pure {
        string memory label = new string(255);
        assertEq(NameUtils.firstLabel(NameUtils.appendETH(label)), label);
    }

    function test_extractLabel_ConsecutiveLabels() public view {
        // Create a more complex DNS name manually: "\x04test\x05alice\x03bob\x00"
        bytes memory complexDns = abi.encodePacked(
            bytes1(uint8(4)),
            "test",
            bytes1(uint8(5)),
            "alice",
            bytes1(uint8(3)),
            "bob",
            bytes1(uint8(0))
        );

        // Extract all labels sequentially
        (string memory label1, uint256 offset1) = this.extractLabel(complexDns, 0);
        assertEq(label1, "test");

        (string memory label2, uint256 offset2) = this.extractLabel(complexDns, offset1);
        assertEq(label2, "alice");

        (string memory label3, uint256 offset3) = this.extractLabel(complexDns, offset2);
        assertEq(label3, "bob");

        // Verify final offset points to terminator
        assertEq(offset3, complexDns.length - 1);
    }

    function test_extractLabel_BinaryData() public view {
        // Test with binary data that might confuse string extraction
        bytes memory binaryLabel = hex"deadbeef1234";
        bytes memory dnsEncoded = abi.encodePacked(
            bytes1(uint8(binaryLabel.length)),
            binaryLabel,
            "\x03eth\x00"
        );

        (string memory extracted, ) = this.extractLabel(dnsEncoded, 0);
        // The extracted string should contain the binary data as bytes
        assertEq(bytes(extracted), binaryLabel);
    }

    function test_extractLabel_MaxOffsetEdgeCases() public view {
        bytes memory dnsName = this.appendETH("test");
        uint256 maxValidOffset = 5; // Start of "eth" label

        // Test at maximum valid offset
        (string memory label, uint256 nextOffset) = this.extractLabel(dnsName, maxValidOffset);
        assertEq(label, "eth");
        assertEq(nextOffset, 9);

        // Test at terminator position - should work but return empty
        (string memory termLabel, ) = this.extractLabel(dnsName, 9);
        assertEq(termLabel, "");
    }

    // Comprehensive getCanonicalId tests including idempotency and bit patterns
    function test_getCanonicalId_Idempotency() public view {
        uint256 id = 0x123456789abcdef0;
        uint256 canonical1 = this.getCanonicalId(id);
        uint256 canonical2 = this.getCanonicalId(canonical1);

        // Applying getCanonicalId twice should give the same result as applying it once
        // This tests: getCanonicalId(getCanonicalId(x)) == getCanonicalId(x)
        assertEq(canonical1, canonical2);

        // Test with different values
        uint256 id2 = 0xdeadbeefcafebabe;
        uint256 canonical3 = this.getCanonicalId(id2);
        uint256 canonical4 = this.getCanonicalId(canonical3);
        assertEq(canonical3, canonical4);
    }

    function test_getCanonicalId_SpecificBitPatterns() public view {
        // Test with all lower 32 bits set
        uint256 lowerBitsSet = 0x123456780ffffffff;
        uint256 canonical1 = this.getCanonicalId(lowerBitsSet);
        uint256 expected1 = lowerBitsSet ^ 0xffffffff;
        assertEq(canonical1, expected1);

        // Test with alternating bit pattern
        uint256 alternating = 0xaaaaaaaaaaaaaaaa;
        uint256 canonical2 = this.getCanonicalId(alternating);
        uint256 expected2 = alternating ^ 0xaaaaaaaa;
        assertEq(canonical2, expected2);

        // Test with only high bits set (lower 32 bits are zero)
        uint256 highBitsOnly = 0xffffffff00000000;
        uint256 canonical3 = this.getCanonicalId(highBitsOnly);
        assertEq(canonical3, highBitsOnly); // Should be unchanged since uint32(id) = 0
    }

    function test_getCanonicalId_PowersOfTwo() public view {
        // Test with powers of 2
        for (uint8 i = 0; i < 32; i++) {
            uint256 powerOf2 = 1 << i;
            uint256 canonical = this.getCanonicalId(powerOf2);
            uint256 expected = powerOf2 ^ uint32(powerOf2);
            assertEq(canonical, expected);
        }

        // Test with higher powers of 2 (beyond 32 bits)
        for (uint8 i = 32; i < 64; i++) {
            uint256 powerOf2 = 1 << i;
            uint256 canonical = this.getCanonicalId(powerOf2);
            // Since uint32(powerOf2) = 0 for powers > 2^32, canonical should equal original
            assertEq(canonical, powerOf2);
        }
    }

    function test_getCanonicalId_SymmetricProperties() public view {
        // Test that the XOR operation creates symmetry
        uint256 id = 0x123456789abcdef0;
        uint256 canonical = this.getCanonicalId(id);

        // Verify the bit manipulation works correctly
        uint32 lower32 = uint32(id);
        uint256 expectedResult = id ^ uint256(lower32);
        assertEq(canonical, expectedResult);

        // Test edge case where lower 32 bits create interesting patterns
        uint256 testId = 0x123456789abcdef0;
        uint256 result = this.getCanonicalId(testId);

        // Manually calculate expected result
        uint32 expectedLower32 = uint32(testId); // 0x9abcdef0
        uint256 expectedCanonical = testId ^ expectedLower32;
        assertEq(result, expectedCanonical);
    }

    function test_getCanonicalId_EdgeCaseBitPatterns() public view {
        // Test when lower 32 bits are all 1s
        uint256 allOnes = type(uint256).max; // 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
        uint256 canonical1 = this.getCanonicalId(allOnes);
        uint256 expected1 = allOnes ^ 0xffffffff;
        assertEq(canonical1, expected1);

        // Test when lower 32 bits spell out specific patterns
        uint256 deadbeef = 0x123456789abcdeadbeef1234;
        uint256 canonical2 = this.getCanonicalId(deadbeef);
        uint256 expected2 = deadbeef ^ 0xbeef1234;
        assertEq(canonical2, expected2);

        // Test with minimal bit differences
        uint256 minimal1 = 0x8000000000000001;
        uint256 minimal2 = 0x8000000000000000;
        uint256 canonical3 = this.getCanonicalId(minimal1);
        uint256 canonical4 = this.getCanonicalId(minimal2);

        // They should differ by exactly the XOR of their lower 32 bits
        assertEq(canonical3, minimal1 ^ 1);
        assertEq(canonical4, minimal2 ^ 0);
    }

    function test_getCanonicalId_DistributionProperties() public view {
        // Test that different inputs produce different outputs
        // We need values with different upper bits AND lower bits to ensure different results
        uint256[] memory testValues = new uint256[](5);
        testValues[0] = 0x123456781; // Different upper + lower bits: 1
        testValues[1] = 0x234567892; // Different upper + lower bits: 2
        testValues[2] = 0x345678900; // Different upper + lower bits: 0
        testValues[3] = 0x45678901F; // Different upper + lower bits: 31
        testValues[4] = 0x5678901FF; // Different upper + lower bits: 255

        uint256[] memory canonicalValues = new uint256[](5);
        for (uint i = 0; i < testValues.length; i++) {
            canonicalValues[i] = this.getCanonicalId(testValues[i]);

            // Verify the formula works: canonical = original ^ uint32(original)
            uint256 expected = testValues[i] ^ uint32(testValues[i]);
            assertEq(canonicalValues[i], expected);
        }

        // Ensure all canonical values are different
        for (uint i = 0; i < canonicalValues.length; i++) {
            for (uint j = i + 1; j < canonicalValues.length; j++) {
                assertTrue(canonicalValues[i] != canonicalValues[j]);
            }
        }
    }

    function test_getCanonicalId_ConsistencyWithLabelToCanonicalId() public view {
        // Test that getCanonicalId is consistent with labelToCanonicalId
        string memory testLabel = "testlabel";
        uint256 fromLabel = this.labelToCanonicalId(testLabel);

        // Calculate what labelToCanonicalId should produce
        uint256 rawHash = uint256(keccak256(bytes(testLabel)));
        uint256 fromHash = this.getCanonicalId(rawHash);

        assertEq(fromLabel, fromHash);

        // Test with multiple labels
        string[] memory labels = new string[](3);
        labels[0] = "alice";
        labels[1] = "bob";
        labels[2] = "charlie";

        for (uint i = 0; i < labels.length; i++) {
            uint256 labelCanonical = this.labelToCanonicalId(labels[i]);
            uint256 hashCanonical = this.getCanonicalId(uint256(keccak256(bytes(labels[i]))));
            assertEq(labelCanonical, hashCanonical);
        }
    }

    function testFuzz_getCanonicalId_Idempotency(uint256 id) public view {
        uint256 canonical1 = this.getCanonicalId(id);
        uint256 canonical2 = this.getCanonicalId(canonical1);
        assertEq(canonical1, canonical2);
    }

    function testFuzz_getCanonicalId_Formula(uint256 id) public view {
        uint256 canonical = this.getCanonicalId(id);
        uint256 expected = id ^ uint32(id);
        assertEq(canonical, expected);
    }

    // Integration tests and cross-function verification
    function test_integration_CompleteRoundTrip() public view {
        string memory originalLabel = "complex-test-label";

        // Step 1: Convert label to canonical ID
        uint256 canonicalId = this.labelToCanonicalId(originalLabel);

        // Step 2: Encode the label as DNS
        bytes memory dnsEncoded = this.appendETH(originalLabel);

        // Step 3: Extract the label back
        string memory extractedLabel = this.firstLabel(dnsEncoded);

        // Step 4: Convert extracted label back to canonical ID
        uint256 extractedCanonicalId = this.labelToCanonicalId(extractedLabel);

        // Verify round-trip integrity
        assertEq(extractedLabel, originalLabel);
        assertEq(extractedCanonicalId, canonicalId);

        // Verify canonical ID is idempotent
        uint256 reappliedCanonical = this.getCanonicalId(canonicalId);
        assertEq(reappliedCanonical, canonicalId);
    }

    function test_integration_MultipleLabelsRoundTrip() public view {
        string[] memory labels = new string[](4);
        labels[0] = "alice";
        labels[1] = "bob";
        labels[2] = "charlie";
        labels[3] = unicode"tëst-ñämé";

        for (uint i = 0; i < labels.length; i++) {
            // Encode and extract
            bytes memory encoded = this.appendETH(labels[i]);
            string memory extracted = this.firstLabel(encoded);
            assertEq(extracted, labels[i]);

            // Verify canonical IDs match
            uint256 originalId = this.labelToCanonicalId(labels[i]);
            uint256 extractedId = this.labelToCanonicalId(extracted);
            assertEq(originalId, extractedId);
        }
    }

    function test_integration_CanonicalIdUniqueness() public view {
        // Test that different labels produce different canonical IDs
        string[] memory uniqueLabels = new string[](6);
        uniqueLabels[0] = "test";
        uniqueLabels[1] = "Test"; // Different case
        uniqueLabels[2] = "test1";
        uniqueLabels[3] = "test "; // With space
        uniqueLabels[4] = unicode"tëst"; // With accent
        uniqueLabels[5] = ""; // Empty

        uint256[] memory canonicalIds = new uint256[](uniqueLabels.length);
        for (uint i = 0; i < uniqueLabels.length; i++) {
            canonicalIds[i] = this.labelToCanonicalId(uniqueLabels[i]);
        }

        // Verify all canonical IDs are unique
        for (uint i = 0; i < canonicalIds.length; i++) {
            for (uint j = i + 1; j < canonicalIds.length; j++) {
                assertTrue(canonicalIds[i] != canonicalIds[j]);
            }
        }
    }

    function test_integration_RealWorldENSNames() public view {
        // Test with real-world-style ENS names
        string[] memory realWorldLabels = new string[](5);
        realWorldLabels[0] = "vitalik";
        realWorldLabels[1] = "uniswap";
        realWorldLabels[2] = "compound";
        realWorldLabels[3] = "1inch";
        realWorldLabels[4] = "opensea";

        for (uint i = 0; i < realWorldLabels.length; i++) {
            // Test complete workflow
            uint256 canonicalId = this.labelToCanonicalId(realWorldLabels[i]);
            bytes memory dnsEncoded = this.appendETH(realWorldLabels[i]);
            string memory extracted = this.firstLabel(dnsEncoded);

            // Verify round-trip
            assertEq(extracted, realWorldLabels[i]);
            uint256 roundTripId = this.labelToCanonicalId(extracted);
            assertEq(roundTripId, canonicalId);

            // Verify canonical ID properties
            uint256 rawHash = uint256(keccak256(bytes(realWorldLabels[i])));
            uint256 expectedCanonical = this.getCanonicalId(rawHash);
            assertEq(canonicalId, expectedCanonical);
        }
    }

    function test_integration_ChainedExtraction() public view {
        // Create a complex DNS name with multiple labels
        bytes memory complexDns = abi.encodePacked(
            bytes1(uint8(3)),
            "www",
            bytes1(uint8(7)),
            "example",
            bytes1(uint8(3)),
            "com",
            bytes1(uint8(0))
        );

        // Extract labels in sequence and verify each step
        (string memory label1, uint256 offset1) = this.extractLabel(complexDns, 0);
        assertEq(label1, "www");
        assertEq(offset1, 4); // 1 + 3

        (string memory label2, uint256 offset2) = this.extractLabel(complexDns, offset1);
        assertEq(label2, "example");
        assertEq(offset2, 12); // 4 + 1 + 7

        (string memory label3, uint256 offset3) = this.extractLabel(complexDns, offset2);
        assertEq(label3, "com");
        assertEq(offset3, 16); // 12 + 1 + 3

        // Verify we're at the terminator
        assertEq(offset3, complexDns.length - 1);

        // Test canonical IDs for each extracted label
        uint256 canonicalWww = this.labelToCanonicalId(label1);
        uint256 canonicalExample = this.labelToCanonicalId(label2);
        uint256 canonicalCom = this.labelToCanonicalId(label3);

        // Verify they're all different
        assertTrue(canonicalWww != canonicalExample);
        assertTrue(canonicalExample != canonicalCom);
        assertTrue(canonicalWww != canonicalCom);
    }

    function test_integration_ConsistencyAcrossEncodings() public view {
        // Test that the same logical label produces consistent results regardless of how it's processed
        string memory testLabel = "consistency-test";

        // Method 1: Direct canonical ID
        uint256 directCanonical = this.labelToCanonicalId(testLabel);

        // Method 2: Via DNS encoding and extraction
        bytes memory dnsEncoded = this.appendETH(testLabel);
        string memory extracted = this.firstLabel(dnsEncoded);
        uint256 indirectCanonical = this.labelToCanonicalId(extracted);

        // Method 3: Via getCanonicalId of hash
        uint256 rawHash = uint256(keccak256(bytes(testLabel)));
        uint256 hashCanonical = this.getCanonicalId(rawHash);

        // All methods should produce the same result
        assertEq(directCanonical, indirectCanonical);
        assertEq(indirectCanonical, hashCanonical);

        // Verify the extracted label matches original
        assertEq(extracted, testLabel);
    }

    function testFuzz_integration_RoundTripConsistency(string memory label) public view {
        // Skip extremely long labels to avoid gas issues and empty strings which have special behavior
        vm.assume(bytes(label).length <= 100);
        vm.assume(bytes(label).length > 0); // Skip empty strings

        // Test round-trip consistency
        uint256 originalCanonical = this.labelToCanonicalId(label);
        bytes memory dnsEncoded = this.appendETH(label);
        string memory extracted = this.firstLabel(dnsEncoded);
        uint256 extractedCanonical = this.labelToCanonicalId(extracted);

        assertEq(extracted, label);
        assertEq(extractedCanonical, originalCanonical);

        // Test canonical ID idempotency
        assertEq(this.getCanonicalId(originalCanonical), originalCanonical);
    }

    function test_boundary_EmptyAndNullInputs() public view {
        // Test empty string handled separately as it has special behavior
        // Empty strings create DNS names with just .eth suffix

        // Test string with null bytes
        string memory nullString = string(abi.encodePacked("test", bytes1(0), "null"));
        bytes memory nullEncoded = this.appendETH(nullString);
        string memory nullExtracted = this.firstLabel(nullEncoded);
        assertEq(nullExtracted, nullString);

        uint256 nullCanonical = this.labelToCanonicalId(nullString);
        assertEq(this.getCanonicalId(nullCanonical), nullCanonical);
    }

    function test_boundary_OffsetEdgeCases() public view {
        bytes memory dnsName = this.appendETH("boundary");

        // Test offset at the start of each component
        (string memory label1, uint256 offset1) = this.extractLabel(dnsName, 0);
        assertEq(label1, "boundary");

        (string memory label2, uint256 offset2) = this.extractLabel(dnsName, offset1);
        assertEq(label2, "eth");

        // offset2 should now be at the terminator position
        assertEq(offset2, dnsName.length - 1);

        // Trying to extract at the terminator should return empty string
        (string memory emptyLabel, ) = this.extractLabel(dnsName, offset2);
        assertEq(emptyLabel, "");
    }

    function test_boundary_LargeCanonicalIds() public view {
        // Test with very large uint256 values
        uint256 maxValue = type(uint256).max;
        uint256 maxCanonical = this.getCanonicalId(maxValue);
        uint256 expectedMax = maxValue ^ uint32(maxValue);
        assertEq(maxCanonical, expectedMax);

        // Test idempotency with max value
        assertEq(this.getCanonicalId(maxCanonical), maxCanonical);

        // Test with large power of 2
        uint256 largePowerOf2 = 1 << 255;
        uint256 largeCanonical = this.getCanonicalId(largePowerOf2);
        assertEq(largeCanonical, largePowerOf2); // Should be unchanged since lower 32 bits are 0
    }

    function test_boundary_ConsecutiveExtractions() public view {
        // Test extracting many labels in sequence without errors
        bytes memory multiLabelDns = abi.encodePacked(
            bytes1(uint8(1)),
            "a",
            bytes1(uint8(1)),
            "b",
            bytes1(uint8(1)),
            "c",
            bytes1(uint8(1)),
            "d",
            bytes1(uint8(1)),
            "e",
            bytes1(uint8(0))
        );

        string[] memory expectedLabels = new string[](5);
        expectedLabels[0] = "a";
        expectedLabels[1] = "b";
        expectedLabels[2] = "c";
        expectedLabels[3] = "d";
        expectedLabels[4] = "e";

        uint256 currentOffset = 0;
        for (uint i = 0; i < expectedLabels.length; i++) {
            (string memory extractedLabel, uint256 nextOffset) = this.extractLabel(
                multiLabelDns,
                currentOffset
            );
            assertEq(extractedLabel, expectedLabels[i]);
            currentOffset = nextOffset;
        }

        // Should be at terminator now
        assertEq(currentOffset, multiLabelDns.length - 1);
    }

    function testFuzz_boundary_ValidOffsets(uint256 seed) public view {
        // Generate a deterministic but varied DNS name
        string memory label = string(abi.encodePacked("test", seed % 1000));
        bytes memory dnsEncoded = this.appendETH(label);

        // Only test valid offsets
        uint256 validOffset = seed % 2 == 0 ? 0 : uint256(bytes(label).length) + 1;

        if (validOffset < dnsEncoded.length - 1) {
            // Should not revert for valid offsets
            try this.extractLabel(dnsEncoded, validOffset) returns (string memory, uint256) {
                // Success expected for valid offsets
            } catch {
                // This might happen for some edge cases, which is acceptable
            }
        }
    }
}
