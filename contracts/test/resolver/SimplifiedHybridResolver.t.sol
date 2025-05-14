// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {SimplifiedHybridResolver} from "../../src/common/SimplifiedHybridResolver.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";
import {NameUtils} from "../../src/common/NameUtils.sol";

contract SimplifiedHybridResolverTest is Test {
    SimplifiedHybridResolver resolver;
    address owner = address(0x123);
    address registry = address(0x456);
    
    bytes32 testNode = 0xde9b09fd7c5f901e23a3f19fecc54828e9c848539801e86591bd9801b019f84f; // example.eth
    bytes32 aliasNode = 0x7d56aa46358ba2f8b77d8e05bcabdd2358370dcf34e87810f8cea77ecb3fc57d; // example.xyz
    address testAddr = address(0x789);
    
    event NamehashMapped(bytes32 indexed namehash, uint256 indexed labelHash, bool isPrimary);
    event AddrChanged(bytes32 indexed node, uint coinType, bytes newAddress);
    
    function setUp() public {
        // Deploy the resolver implementation
        SimplifiedHybridResolver implementation = new SimplifiedHybridResolver();
        
        // Deploy the factory
        VerifiableFactory factory = new VerifiableFactory();
        
        // Deploy the resolver proxy
        bytes memory initData = abi.encodeWithSelector(
            SimplifiedHybridResolver.initialize.selector,
            owner,
            registry
        );
        
        uint256 salt = 123456; // Use a consistent salt for deterministic addresses
        address proxyAddress = factory.deployProxy(address(implementation), salt, initData);
        resolver = SimplifiedHybridResolver(proxyAddress);
        
        // Set up the test environment
        vm.startPrank(owner);
    }
    
    function testInitialization() public {
        assertEq(resolver.owner(), owner);
        assertEq(resolver.registry(), registry);
    }
    
    function testSetAddr() public {
        // Record logs to verify events
        vm.recordLogs();
        
        // Set the address
        resolver.setAddr(testNode, testAddr);
        
        // Get the logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Verify events were emitted
        bool foundNamehashMapped = false;
        bool foundAddrChanged = false;
        bool foundAddressChanged = false;
        
        for (uint i = 0; i < logs.length; i++) {
            // Check for NamehashMapped event
            if (logs[i].topics[0] == keccak256("NamehashMapped(bytes32,uint256,bool)")) {
                foundNamehashMapped = true;
                assertEq(logs[i].topics[1], bytes32(testNode));
                assertEq(logs[i].topics[2], bytes32(uint256(testNode)));
            }
            // Check for AddrChanged event
            else if (logs[i].topics[0] == keccak256("AddrChanged(bytes32,address)")) {
                foundAddrChanged = true;
                assertEq(logs[i].topics[1], testNode);
            }
            // Check for AddressChanged event
            else if (logs[i].topics[0] == keccak256("AddressChanged(bytes32,uint256,bytes)")) {
                foundAddressChanged = true;
                assertEq(logs[i].topics[1], testNode);
            }
        }
        
        assertTrue(foundNamehashMapped, "NamehashMapped event not emitted");
        assertTrue(foundAddrChanged, "AddrChanged event not emitted");
        assertTrue(foundAddressChanged, "AddressChanged event not emitted");
        
        // Verify the address was set correctly
        assertEq(resolver.addr(testNode), testAddr);
        
        // Verify the label hash was created
        assertEq(resolver.getLabelHash(testNode), uint256(testNode));
        
        // Verify the primary namehash was set
        assertEq(resolver.getPrimaryNamehash(uint256(testNode)), testNode);
    }
    
    function testAliasing() public {
        // Set the address for the primary name
        resolver.setAddr(testNode, testAddr);
        
        // Map the alias to the same label hash
        uint256 labelHash = resolver.getLabelHash(testNode);
        
        vm.expectEmit(true, true, false, true);
        emit NamehashMapped(aliasNode, labelHash, false);
        
        resolver.mapToExistingLabelHash(aliasNode, labelHash);
        
        // Verify both names resolve to the same address
        assertEq(resolver.addr(testNode), testAddr);
        assertEq(resolver.addr(aliasNode), testAddr);
        
        // Verify the label hash mapping
        assertEq(resolver.getLabelHash(aliasNode), labelHash);
        
        // Verify the primary namehash is still the original
        assertEq(resolver.getPrimaryNamehash(labelHash), testNode);
    }
    
    function testSetAddrWithCoinType() public {
        uint256 coinType = 60; // ETH
        bytes memory addrBytes = abi.encodePacked(testAddr);
        
        // Set the address with coin type
        resolver.setAddr(testNode, coinType, addrBytes);
        
        // Verify the address was set correctly
        assertEq(resolver.addr(testNode, coinType), addrBytes);
    }
    
    function testMapNamehash() public {
        uint256 customLabelHash = 12345;
        
        vm.expectEmit(true, true, false, true);
        emit NamehashMapped(testNode, customLabelHash, true);
        
        // Map the namehash to a custom label hash
        resolver.mapNamehash(testNode, customLabelHash, true);
        
        // Verify the mapping
        assertEq(resolver.getLabelHash(testNode), customLabelHash);
        assertEq(resolver.getPrimaryNamehash(customLabelHash), testNode);
    }
    
    function testMapToExistingLabelHashFailsForNonExistentLabel() public {
        uint256 nonExistentLabelHash = 12345;
        
        // Should revert because the label hash doesn't exist
        vm.expectRevert("Target labelHash does not exist");
        resolver.mapToExistingLabelHash(aliasNode, nonExistentLabelHash);
    }
    
    function testAuthorization() public {
        // Set up a non-owner address
        address nonOwner = address(0xabc);
        
        // Stop pranking as owner
        vm.stopPrank();
        
        // Start pranking as non-owner
        vm.startPrank(nonOwner);
        
        // Should revert because caller is not authorized
        vm.expectRevert();
        resolver.setAddr(testNode, testAddr);
        
        // Should revert because caller is not the owner
        vm.expectRevert();
        resolver.mapNamehash(testNode, 12345, true);
    }
    
    function testMultipleAliases() public {
        // Set up multiple aliases
        bytes32 alias1Node = 0x1111111111111111111111111111111111111111111111111111111111111111;
        bytes32 alias2Node = 0x2222222222222222222222222222222222222222222222222222222222222222;
        
        // Set the address for the primary name
        resolver.setAddr(testNode, testAddr);
        uint256 labelHash = resolver.getLabelHash(testNode);
        
        // Map aliases to the same label hash
        resolver.mapToExistingLabelHash(alias1Node, labelHash);
        resolver.mapToExistingLabelHash(alias2Node, labelHash);
        
        // Verify all names resolve to the same address
        assertEq(resolver.addr(testNode), testAddr);
        assertEq(resolver.addr(alias1Node), testAddr);
        assertEq(resolver.addr(alias2Node), testAddr);
    }
    
    function testClearRecords() public {
        // Set the address
        resolver.setAddr(testNode, testAddr);
        
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
}
