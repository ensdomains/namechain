// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {UniversalResolverV2} from "../../src/universalResolver/UniversalResolverV2.sol";
import {PermissionedRegistryV2} from "../../src/common/PermissionedRegistryV2.sol";
import {RegistryDatastore} from "../../src/common/RegistryDatastore.sol";
import {SimpleRegistryMetadata} from "../../src/common/SimpleRegistryMetadata.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";
import {SingleNameResolver} from "../../src/common/SingleNameResolver.sol";
import {NameUtils} from "../../src/common/NameUtils.sol";
import {IRegistry} from "../../src/common/IRegistry.sol";
import {NameCoder} from "../../src/universalResolver/AbstractUniversalResolver.sol";

contract UniversalResolverV2Test is Test {
    UniversalResolverV2 resolver;
    PermissionedRegistryV2 rootRegistry;
    PermissionedRegistryV2 ethRegistry;
    PermissionedRegistryV2 exampleRegistry;
    RegistryDatastore datastore;
    VerifiableFactory factory;
    SingleNameResolver resolverImplementation;
    
    address deployer = address(0x123);
    address user = address(0x456);
    address testAddr = address(0x789);
    
    // Constants
    uint256 constant ROLE_ADMIN = 1 << 0;
    uint256 constant ROLE_REGISTRAR = 1 << 1;
    uint256 constant ROLE_SET_RESOLVER = 1 << 2;
    uint256 constant ROLE_SET_SUBREGISTRY = 1 << 3;
    uint256 constant ROLE_SET_TOKEN_OBSERVER = 1 << 4;
    uint256 constant ROLE_RENEW = 1 << 5;
    
    function setUp() public {
        // Deploy the datastore
        datastore = new RegistryDatastore();
        
        // Deploy the registries
        uint256 deployerRoles = ROLE_ADMIN | ROLE_REGISTRAR | ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY | ROLE_SET_TOKEN_OBSERVER | ROLE_RENEW;
        vm.startPrank(deployer);
        
        rootRegistry = new PermissionedRegistryV2(datastore, SimpleRegistryMetadata(address(0)), deployerRoles);
        ethRegistry = new PermissionedRegistryV2(datastore, SimpleRegistryMetadata(address(0)), deployerRoles);
        exampleRegistry = new PermissionedRegistryV2(datastore, SimpleRegistryMetadata(address(0)), deployerRoles);
        
        // Deploy the resolver implementation
        resolverImplementation = new SingleNameResolver();
        
        // Deploy the factory
        factory = new VerifiableFactory();
        
        // Set the resolver factory for all registries
        rootRegistry.setResolverFactory(address(factory), address(resolverImplementation));
        ethRegistry.setResolverFactory(address(factory), address(resolverImplementation));
        exampleRegistry.setResolverFactory(address(factory), address(resolverImplementation));
        
        // Set up the registry hierarchy
        rootRegistry.register("eth", deployer, ethRegistry, address(0), deployerRoles, type(uint64).max);
        ethRegistry.register("example", deployer, exampleRegistry, address(0), deployerRoles, type(uint64).max);
        
        // Deploy the universal resolver
        string[] memory gateways = new string[](0);
        resolver = new UniversalResolverV2(rootRegistry, gateways);
        
        vm.stopPrank();
    }
    
    function testFindResolver() public {
        vm.startPrank(deployer);
        
        // Deploy a resolver for example.eth
        address resolverAddress = exampleRegistry.deployResolver("example", user);
        
        // Set up the resolver with an ETH address
        vm.stopPrank();
        vm.startPrank(user);
        SingleNameResolver(resolverAddress).setAddr(testAddr);
        vm.stopPrank();
        
        // Encode the name example.eth
        bytes memory encodedName = dnsEncodeName("example.eth");
        
        // Find the resolver
        (address foundResolver, bytes32 node, uint256 offset) = resolver.findResolver(encodedName);
        
        // Verify the resolver was found correctly
        assertEq(foundResolver, resolverAddress);
        assertEq(node, namehash("example.eth"));
        
        vm.startPrank(deployer);
    }
    
    function testResolveAddr() public {
        vm.startPrank(deployer);
        
        // Deploy a resolver for example.eth
        address resolverAddress = exampleRegistry.deployResolver("example", user);
        
        // Set up the resolver with an ETH address
        vm.stopPrank();
        vm.startPrank(user);
        SingleNameResolver(resolverAddress).setAddr(testAddr);
        vm.stopPrank();
        
        // Encode the name example.eth
        bytes memory encodedName = dnsEncodeName("example.eth");
        
        // Resolve the address
        bytes memory result = resolver.resolve(
            encodedName,
            abi.encodeWithSelector(bytes4(keccak256("addr(bytes32)")))
        );
        
        // Decode the result
        address resolvedAddr = abi.decode(result, (address));
        
        // Verify the address was resolved correctly
        assertEq(resolvedAddr, testAddr);
        
        vm.startPrank(deployer);
    }
    
    function testResolveText() public {
        vm.startPrank(deployer);
        
        // Deploy a resolver for example.eth
        address resolverAddress = exampleRegistry.deployResolver("example", user);
        
        // Set up the resolver with a text record
        vm.stopPrank();
        vm.startPrank(user);
        SingleNameResolver(resolverAddress).setText("email", "test@example.com");
        vm.stopPrank();
        
        // Encode the name example.eth
        bytes memory encodedName = dnsEncodeName("example.eth");
        
        // Resolve the text record
        bytes memory result = resolver.resolve(
            encodedName,
            abi.encodeWithSelector(bytes4(keccak256("text(bytes32,string)")), bytes32(0), "email")
        );
        
        // Decode the result
        string memory resolvedText = abi.decode(result, (string));
        
        // Verify the text record was resolved correctly
        assertEq(resolvedText, "test@example.com");
        
        vm.startPrank(deployer);
    }
    
    function testResolveContenthash() public {
        vm.startPrank(deployer);
        
        // Deploy a resolver for example.eth
        address resolverAddress = exampleRegistry.deployResolver("example", user);
        
        // Set up the resolver with a content hash
        vm.stopPrank();
        vm.startPrank(user);
        bytes memory hash = hex"1234567890";
        SingleNameResolver(resolverAddress).setContenthash(hash);
        vm.stopPrank();
        
        // Encode the name example.eth
        bytes memory encodedName = dnsEncodeName("example.eth");
        
        // Resolve the content hash
        bytes memory result = resolver.resolve(
            encodedName,
            abi.encodeWithSelector(bytes4(keccak256("contenthash(bytes32)")))
        );
        
        // Decode the result
        bytes memory resolvedHash = abi.decode(result, (bytes));
        
        // Verify the content hash was resolved correctly
        assertEq(resolvedHash, hash);
        
        vm.startPrank(deployer);
    }
    
    function testAliasing() public {
        vm.startPrank(deployer);
        
        // Create a .xyz TLD
        PermissionedRegistryV2 xyzRegistry = new PermissionedRegistryV2(datastore, SimpleRegistryMetadata(address(0)), ROLE_ADMIN | ROLE_REGISTRAR | ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY | ROLE_SET_TOKEN_OBSERVER | ROLE_RENEW);
        xyzRegistry.setResolverFactory(address(factory), address(resolverImplementation));
        
        // Register .xyz in the root registry
        rootRegistry.register("xyz", deployer, xyzRegistry, address(0), ROLE_ADMIN | ROLE_REGISTRAR | ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY | ROLE_SET_TOKEN_OBSERVER | ROLE_RENEW, type(uint64).max);
        
        // Register example.xyz pointing to the same registry as example.eth
        xyzRegistry.register("example", deployer, exampleRegistry, address(0), ROLE_ADMIN | ROLE_REGISTRAR | ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY | ROLE_SET_TOKEN_OBSERVER | ROLE_RENEW, type(uint64).max);
        
        // Deploy a resolver for example.eth
        address resolverAddress = exampleRegistry.deployResolver("example", user);
        
        // Set up the resolver with an ETH address
        vm.stopPrank();
        vm.startPrank(user);
        SingleNameResolver(resolverAddress).setAddr(testAddr);
        vm.stopPrank();
        
        // Encode the names
        bytes memory encodedNameEth = dnsEncodeName("example.eth");
        bytes memory encodedNameXyz = dnsEncodeName("example.xyz");
        
        // Resolve the addresses
        bytes memory resultEth = resolver.resolve(
            encodedNameEth,
            abi.encodeWithSelector(bytes4(keccak256("addr(bytes32)")))
        );
        
        bytes memory resultXyz = resolver.resolve(
            encodedNameXyz,
            abi.encodeWithSelector(bytes4(keccak256("addr(bytes32)")))
        );
        
        // Decode the results
        address resolvedAddrEth = abi.decode(resultEth, (address));
        address resolvedAddrXyz = abi.decode(resultXyz, (address));
        
        // Verify both names resolve to the same address
        assertEq(resolvedAddrEth, testAddr);
        assertEq(resolvedAddrXyz, testAddr);
        assertEq(resolvedAddrEth, resolvedAddrXyz);
        
        vm.startPrank(deployer);
    }
    
    // Helper functions
    function dnsEncodeName(string memory name) internal pure returns (bytes memory) {
        bytes memory nameBytes = bytes(name);
        bytes memory result = new bytes(nameBytes.length + 2);
        
        uint256 i = 0;
        uint256 labelStart = 0;
        
        for (uint256 j = 0; j < nameBytes.length; j++) {
            if (nameBytes[j] == '.') {
                result[i] = bytes1(uint8(j - labelStart));
                i++;
                for (uint256 k = labelStart; k < j; k++) {
                    result[i] = nameBytes[k];
                    i++;
                }
                labelStart = j + 1;
            }
        }
        
        result[i] = bytes1(uint8(nameBytes.length - labelStart));
        i++;
        for (uint256 k = labelStart; k < nameBytes.length; k++) {
            result[i] = nameBytes[k];
            i++;
        }
        
        result[i] = 0;
        
        return result;
    }
    
    function namehash(string memory name) internal pure returns (bytes32) {
        bytes32 node = 0;
        
        if (bytes(name).length == 0) {
            return node;
        }
        
        bytes memory nameBytes = bytes(name);
        uint256 labelStart = 0;
        uint256 labelEnd = 0;
        
        for (uint256 i = 0; i < nameBytes.length; i++) {
            if (nameBytes[i] == '.' || i == nameBytes.length - 1) {
                if (i == nameBytes.length - 1) {
                    labelEnd = i + 1;
                } else {
                    labelEnd = i;
                }
                
                bytes32 labelHash = keccak256(abi.encodePacked(substring(name, labelStart, labelEnd - labelStart)));
                node = keccak256(abi.encodePacked(node, labelHash));
                
                labelStart = i + 1;
            }
        }
        
        return node;
    }
    
    function substring(string memory str, uint256 startIndex, uint256 length) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(length);
        
        for (uint256 i = 0; i < length; i++) {
            result[i] = strBytes[startIndex + i];
        }
        
        return string(result);
    }
}
