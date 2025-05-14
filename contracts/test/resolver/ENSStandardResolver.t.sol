// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ENSStandardResolver} from "../../src/common/ENSStandardResolver.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";
import {NameUtils} from "../../src/common/NameUtils.sol";

contract ENSStandardResolverTest is Test {
    ENSStandardResolver resolver;
    address owner = address(0x123);
    address registry = address(0x456);
    
    bytes32 testNode = 0xde9b09fd7c5f901e23a3f19fecc54828e9c848539801e86591bd9801b019f84f; // example.eth
    bytes32 aliasNode = 0x7d56aa46358ba2f8b77d8e05bcabdd2358370dcf34e87810f8cea77ecb3fc57d; // example.xyz
    address testAddr = address(0x789);
    string testLabel = "example";
    
    event NamehashMapped(bytes32 indexed namehash, uint256 indexed labelHash, bool isPrimary);
    event LabelRegistered(string label, uint256 indexed labelHash);
    event AddrChanged(bytes32 indexed node, address newAddress);
    event AddressChanged(bytes32 indexed node, uint coinType, bytes newAddress);
    
    function setUp() public {
        // Deploy the resolver implementation
        ENSStandardResolver implementation = new ENSStandardResolver();
        
        // Deploy the factory
        VerifiableFactory factory = new VerifiableFactory();
        
        // Deploy the resolver proxy
        bytes memory initData = abi.encodeWithSelector(
            ENSStandardResolver.initialize.selector,
            owner,
            registry
        );
        
        uint256 salt = 123456; // Use a consistent salt for deterministic addresses
        address proxyAddress = factory.deployProxy(address(implementation), salt, initData);
        resolver = ENSStandardResolver(proxyAddress);
        
        // Set up the test environment
        vm.startPrank(owner);
    }
    
    function testInitialization() public {
        assertEq(resolver.owner(), owner);
        assertEq(resolver.registry(), registry);
    }
    
    function testComputeLabelHash() public {
        uint256 expectedLabelHash = uint256(keccak256(bytes(testLabel)));
        uint256 computedLabelHash = resolver.computeLabelHash(testLabel);
        assertEq(computedLabelHash, expectedLabelHash);
    }
    
    function testSetAddrWithLabel() public {
        // Record logs to verify events
        vm.recordLogs();
        
        // Set the address with label
        resolver.setAddrWithLabel(testNode, testLabel, testAddr);
        
        // Get the logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Verify events were emitted
        bool foundNamehashMapped = false;
        bool foundLabelRegistered = false;
        bool foundAddrChanged = false;
        
        for (uint i = 0; i < logs.length; i++) {
            // Check for NamehashMapped event
            if (logs[i].topics[0] == keccak256("NamehashMapped(bytes32,uint256,bool)")) {
                foundNamehashMapped = true;
                assertEq(logs[i].topics[1], testNode);
                
                // Compute expected label hash
                uint256 expectedLabelHash = uint256(keccak256(bytes(testLabel)));
                assertEq(logs[i].topics[2], bytes32(expectedLabelHash));
            }
            // Check for LabelRegistered event
            else if (logs[i].topics[0] == keccak256("LabelRegistered(string,uint256)")) {
                foundLabelRegistered = true;
                
                // Compute expected label hash
                uint256 expectedLabelHash = uint256(keccak256(bytes(testLabel)));
                assertEq(logs[i].topics[1], bytes32(expectedLabelHash));
            }
            // Check for AddrChanged event
            else if (logs[i].topics[0] == keccak256("AddrChanged(bytes32,address)")) {
                foundAddrChanged = true;
                assertEq(logs[i].topics[1], testNode);
            }
        }
        
        assertTrue(foundNamehashMapped, "NamehashMapped event not emitted");
        assertTrue(foundLabelRegistered, "LabelRegistered event not emitted");
        assertTrue(foundAddrChanged, "AddrChanged event not emitted");
        
        // Verify the address was set correctly
        assertEq(resolver.addr(testNode), testAddr);
        
        // Verify the label hash was created correctly
        uint256 expectedLabelHash = uint256(keccak256(bytes(testLabel)));
        assertEq(resolver.getLabelHash(testNode), expectedLabelHash);
        
        // Verify the primary namehash was set
        assertEq(resolver.getPrimaryNamehash(expectedLabelHash), testNode);
    }
    
    // Removed testAliasing as aliasing is now handled at the registry level, not the resolver level
    
    function testSetAddrWithLabelAndCoinType() public {
        uint256 coinType = 60; // ETH
        bytes memory addrBytes = abi.encodePacked(testAddr);
        
        // Set the address with label and coin type
        resolver.setAddrWithLabel(testNode, testLabel, coinType, addrBytes);
        
        // Verify the address was set correctly
        assertEq(resolver.addr(testNode, coinType), addrBytes);
    }
    
    function testMapNamehashWithLabel() public {
        uint256 expectedLabelHash = uint256(keccak256(bytes(testLabel)));
        
        vm.expectEmit(true, true, false, true);
        emit NamehashMapped(testNode, expectedLabelHash, true);
        
        vm.expectEmit(false, true, false, true);
        emit LabelRegistered(testLabel, expectedLabelHash);
        
        // Map the namehash to the label
        resolver.mapNamehashWithLabel(testNode, testLabel, true);
        
        // Verify the mapping
        assertEq(resolver.getLabelHash(testNode), expectedLabelHash);
        assertEq(resolver.getPrimaryNamehash(expectedLabelHash), testNode);
    }
    
    // Removed testMapToExistingLabelFailsForNonExistentLabel as aliasing is now handled at the registry level
    
    function testAuthorization() public {
        // Set up a non-owner address
        address nonOwner = address(0xabc);
        
        // Stop pranking as owner
        vm.stopPrank();
        
        // Start pranking as non-owner
        vm.startPrank(nonOwner);
        
        // Should revert because caller is not authorized
        vm.expectRevert();
        resolver.setAddrWithLabel(testNode, testLabel, testAddr);
        
        // Should revert because caller is not the owner
        vm.expectRevert();
        resolver.mapNamehashWithLabel(testNode, testLabel, true);
    }
    
    // Removed testMultipleAliases as aliasing is now handled at the registry level, not the resolver level
    
    function testClearRecords() public {
        // Set the address
        resolver.setAddrWithLabel(testNode, testLabel, testAddr);
        
        // Clear the records
        resolver.clearRecords(testNode);
        
        // Verify the address was cleared
        assertEq(resolver.addr(testNode), address(0));
    }
    
    function testSupportsInterface() public {
        // Test for AddrResolver interface
        bytes4 addrResolverInterface = 0x3b3b57de;
        assertTrue(resolver.supportsInterface(addrResolverInterface));
        
        // Test for ERC165 interface
        bytes4 erc165Interface = 0x01ffc9a7;
        assertTrue(resolver.supportsInterface(erc165Interface));
    }
    
    function testSetAddrRevert() public {
        // Should revert because setAddr is not supported
        vm.expectRevert("Use setAddrWithLabel instead");
        resolver.setAddr(testNode, testAddr);
        
        // Should revert because setAddr with coin type is not supported
        vm.expectRevert("Use setAddrWithLabel instead");
        resolver.setAddr(testNode, 60, abi.encodePacked(testAddr));
    }
}
