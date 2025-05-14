// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {RegistryAwareResolver} from "../../src/common/RegistryAwareResolver.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";
import {NameUtils} from "../../src/common/NameUtils.sol";
import {IRegistry} from "../../src/common/IRegistry.sol";
import {MockRegistry} from "../mocks/MockRegistry.sol";

contract RegistryAwareResolverTest is Test {
    RegistryAwareResolver resolver;
    MockRegistry mockRegistry;
    address owner = address(0x123);
    
    bytes32 testNode = 0xde9b09fd7c5f901e23a3f19fecc54828e9c848539801e86591bd9801b019f84f; // example.eth
    bytes32 aliasNode = 0x7d56aa46358ba2f8b77d8e05bcabdd2358370dcf34e87810f8cea77ecb3fc57d; // example.xyz
    address testAddr = address(0x789);
    
    event AddrChanged(bytes32 indexed node, address newAddress);
    event AddressChanged(bytes32 indexed node, uint coinType, bytes newAddress);
    
    function setUp() public {
        // Deploy the mock registry
        mockRegistry = new MockRegistry();
        
        // Deploy the resolver implementation
        RegistryAwareResolver implementation = new RegistryAwareResolver();
        
        // Deploy the factory
        VerifiableFactory factory = new VerifiableFactory();
        
        // Deploy the resolver proxy
        bytes memory initData = abi.encodeWithSelector(
            RegistryAwareResolver.initialize.selector,
            owner,
            IRegistry(address(mockRegistry))
        );
        
        uint256 salt = 123456; // Use a consistent salt for deterministic addresses
        address proxyAddress = factory.deployProxy(address(implementation), salt, initData);
        resolver = RegistryAwareResolver(proxyAddress);
        
        // Set up the test environment
        vm.startPrank(owner);
    }
    
    function testInitialization() public {
        assertEq(resolver.owner(), owner);
        assertEq(address(resolver.registry()), address(mockRegistry));
    }
    
    function testSetAddr() public {
        // Record logs to verify events
        vm.recordLogs();
        
        // Set the address
        resolver.setAddr(testNode, testAddr);
        
        // Get the logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Verify events were emitted
        bool foundAddrChanged = false;
        
        for (uint i = 0; i < logs.length; i++) {
            // Check for AddrChanged event
            if (logs[i].topics[0] == keccak256("AddrChanged(bytes32,address)")) {
                foundAddrChanged = true;
                assertEq(logs[i].topics[1], testNode);
                
                // Decode the address from the event data
                address decodedAddr = abi.decode(logs[i].data, (address));
                assertEq(decodedAddr, testAddr);
            }
        }
        
        assertTrue(foundAddrChanged, "AddrChanged event not emitted");
        
        // Verify the address was set correctly
        assertEq(resolver.addr(testNode), testAddr);
    }
    
    function testSetAddrWithCoinType() public {
        uint256 coinType = 60; // ETH
        bytes memory addrBytes = abi.encodePacked(testAddr);
        
        // Record logs to verify events
        vm.recordLogs();
        
        // Set the address with coin type
        resolver.setAddr(testNode, coinType, addrBytes);
        
        // Get the logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Verify events were emitted
        bool foundAddressChanged = false;
        bool foundAddrChanged = false;
        
        for (uint i = 0; i < logs.length; i++) {
            // Check for AddressChanged event
            if (logs[i].topics[0] == keccak256("AddressChanged(bytes32,uint256,bytes)")) {
                foundAddressChanged = true;
                assertEq(logs[i].topics[1], testNode);
            }
            // Check for AddrChanged event
            else if (logs[i].topics[0] == keccak256("AddrChanged(bytes32,address)")) {
                foundAddrChanged = true;
                assertEq(logs[i].topics[1], testNode);
            }
        }
        
        assertTrue(foundAddressChanged, "AddressChanged event not emitted");
        assertTrue(foundAddrChanged, "AddrChanged event not emitted");
        
        // Verify the address was set correctly
        assertEq(resolver.addr(testNode, coinType), addrBytes);
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
