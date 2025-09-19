// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import "../src/common/NameUtils.sol";

contract TestNameUtils is Test {
    function test_labelToCanonicalId_consistency() public pure {
        string memory label = "test";
        uint256 canonicalId = NameUtils.labelToCanonicalId(label);
        
        // Should be deterministic
        uint256 canonicalId2 = NameUtils.labelToCanonicalId(label);
        assertEq(canonicalId, canonicalId2, "labelToCanonicalId should be deterministic");
        
        // Should be different for different labels
        uint256 differentCanonicalId = NameUtils.labelToCanonicalId("different");
        assertNotEq(canonicalId, differentCanonicalId, "Different labels should have different canonical IDs");
    }
    
    function test_getCanonicalId_clears_lower_32_bits() public pure {
        // Test with a value that has bits set in lower 32 positions
        uint256 testValue = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        uint256 canonicalId = NameUtils.getCanonicalId(testValue);
        
        // Lower 32 bits should be cleared
        uint256 expected = testValue ^ uint32(testValue);
        assertEq(canonicalId, expected, "getCanonicalId should XOR with uint32(id)");
        
        // Verify lower 32 bits are indeed zero
        uint256 lower32Bits = canonicalId & 0xFFFFFFFF;
        assertEq(lower32Bits, 0, "Lower 32 bits should be zero");
    }
    
    function test_getCanonicalId_with_various_inputs() public pure {
        // Test with zero
        uint256 zero = 0;
        assertEq(NameUtils.getCanonicalId(zero), 0, "getCanonicalId(0) should be 0");
        
        // Test with value that has only upper bits set  
        uint256 upperBitsOnly = uint256(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) << 32;
        assertEq(NameUtils.getCanonicalId(upperBitsOnly), upperBitsOnly, "Upper bits only should remain unchanged");
        
        // Test with value that has only lower bits set
        uint256 lowerBitsOnly = 0xFFFFFFFF;
        assertEq(NameUtils.getCanonicalId(lowerBitsOnly), 0, "Lower bits only should result in zero");
        
        // Test with specific patterns
        uint256 pattern1 = 0x123456789ABCDEF0FEDCBA0987654321;
        uint256 canonical1 = NameUtils.getCanonicalId(pattern1);
        uint256 expected1 = pattern1 ^ uint32(pattern1);
        assertEq(canonical1, expected1, "Pattern 1 should match expected XOR result");
    }
    
    function test_getCanonicalId_idempotent() public pure {
        uint256 testValue = 0x123456789ABCDEF0FEDCBA0987654321;
        uint256 canonical1 = NameUtils.getCanonicalId(testValue);
        uint256 canonical2 = NameUtils.getCanonicalId(canonical1);
        
        // Applying getCanonicalId to a canonical ID should not change it
        assertEq(canonical1, canonical2, "getCanonicalId should be idempotent");
    }
    
    function test_getCanonicalId_preserves_upper_bits() public pure {
        uint256 testValue = 0x123456789ABCDEF0FEDCBA0987654321;
        uint256 canonicalId = NameUtils.getCanonicalId(testValue);
        
        // Upper 224 bits should be preserved
        uint256 upperBits = testValue >> 32;
        uint256 canonicalUpperBits = canonicalId >> 32;
        assertEq(upperBits, canonicalUpperBits, "Upper bits should be preserved");
    }
    
    function test_dnsEncodeEthLabel_basic() public pure {
        string memory label = "test";
        bytes memory encoded = NameUtils.dnsEncodeEthLabel(label);
        
        // Should be: length_byte + label + "\x03eth\x00"
        bytes memory expected = abi.encodePacked(
            bytes1(uint8(4)), // length of "test"
            "test",
            "\x03eth\x00"
        );
        
        assertEq(encoded, expected, "DNS encoding should match expected format");
    }
    
    function test_dnsEncodeEthLabel_empty() public pure {
        string memory label = "";
        bytes memory encoded = NameUtils.dnsEncodeEthLabel(label);
        
        bytes memory expected = abi.encodePacked(
            bytes1(uint8(0)), // length of empty string
            "",
            "\x03eth\x00"
        );
        
        assertEq(encoded, expected, "Empty label should encode correctly");
    }
    
    function test_dnsEncodeEthLabel_long() public pure {
        string memory label = "verylonglabelnamethatshouldstillwork";
        bytes memory encoded = NameUtils.dnsEncodeEthLabel(label);
        
        bytes memory expected = abi.encodePacked(
            bytes1(uint8(bytes(label).length)),
            label,
            "\x03eth\x00"
        );
        
        assertEq(encoded, expected, "Long label should encode correctly");
    }
    
    function test_getCanonicalId_maintains_bit_structure() public pure {
        // Test that the XOR operation correctly maintains the bit structure
        uint256 testValue = 0x0123456789ABCDEF0FEDCBA987654321;
        uint256 canonicalId = NameUtils.getCanonicalId(testValue);
        
        // Manually calculate expected result
        uint32 lowerBits = uint32(testValue);
        uint256 expected = testValue ^ uint256(lowerBits);
        
        assertEq(canonicalId, expected, "Bit structure should be maintained correctly");
        
        // Verify specific bit positions
        for (uint i = 0; i < 32; i++) {
            uint256 bitMask = 1 << i;
            uint256 canonicalBit = canonicalId & bitMask;
            assertEq(canonicalBit, 0, string(abi.encodePacked("Bit ", vm.toString(i), " should be zero")));
        }
    }
}