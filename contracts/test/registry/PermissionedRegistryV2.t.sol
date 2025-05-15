// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {PermissionedRegistryV2} from "../../src/common/PermissionedRegistryV2.sol";
import {RegistryDatastore} from "../../src/common/RegistryDatastore.sol";
import {SimpleRegistryMetadata} from "../../src/common/SimpleRegistryMetadata.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";
import {SingleNameResolver} from "../../src/common/SingleNameResolver.sol";
import {NameUtils} from "../../src/common/NameUtils.sol";
import {IRegistry} from "../../src/common/IRegistry.sol";

contract PermissionedRegistryV2Test is Test {
    PermissionedRegistryV2 registry;
    RegistryDatastore datastore;
    VerifiableFactory factory;
    SingleNameResolver resolverImplementation;

    address deployer = address(0x123);
    address user = address(0x456);

    // Constants
    uint256 constant ROLE_ADMIN = 1 << 0;
    uint256 constant ROLE_REGISTRAR = 1 << 1;
    uint256 constant ROLE_SET_RESOLVER = 1 << 2;
    uint256 constant ROLE_SET_SUBREGISTRY = 1 << 3;
    uint256 constant ROLE_SET_TOKEN_OBSERVER = 1 << 4;
    uint256 constant ROLE_RENEW = 1 << 5;

    // Events
    event ResolverDeployed(string indexed label, address resolver, address owner);
    event ResolverFactorySet(address factory, address implementation);

    function setUp() public {
        // Deploy the datastore
        datastore = new RegistryDatastore();

        // Deploy the registry
        uint256 deployerRoles = ROLE_ADMIN | ROLE_REGISTRAR | ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY
            | ROLE_SET_TOKEN_OBSERVER | ROLE_RENEW;
        vm.startPrank(deployer);
        registry = new PermissionedRegistryV2(datastore, SimpleRegistryMetadata(address(0)), deployerRoles);

        // Deploy the resolver implementation
        resolverImplementation = new SingleNameResolver();

        // Deploy the factory
        factory = new VerifiableFactory();

        // Set the resolver factory
        registry.setResolverFactory(address(factory), address(resolverImplementation));

        vm.stopPrank();
    }

    function testSetResolverFactory() public {
        vm.startPrank(deployer);

        // Record logs to verify events
        vm.recordLogs();

        // Set a new resolver factory
        address newFactory = address(0x789);
        address newImplementation = address(0xabc);
        registry.setResolverFactory(newFactory, newImplementation);

        // Get the logs
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Verify events were emitted
        bool foundResolverFactorySet = false;

        for (uint256 i = 0; i < logs.length; i++) {
            // Check for ResolverFactorySet event
            if (logs[i].topics[0] == keccak256("ResolverFactorySet(address,address)")) {
                foundResolverFactorySet = true;
                (address factoryAddr, address implAddr) = abi.decode(logs[i].data, (address, address));
                assertEq(factoryAddr, newFactory);
                assertEq(implAddr, newImplementation);
            }
        }

        assertTrue(foundResolverFactorySet, "ResolverFactorySet event not emitted");

        // Verify the factory was set correctly
        assertEq(registry.resolverFactory(), newFactory);
        assertEq(registry.resolverImplementation(), newImplementation);

        vm.stopPrank();
    }

    function testDeployResolver() public {
        vm.startPrank(deployer);

        // Register a name
        string memory label = "example";
        uint64 expires = uint64(block.timestamp + 365 days);
        uint256 roleBitmap = ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY | ROLE_RENEW;
        registry.register(label, user, IRegistry(address(0)), address(0), roleBitmap, expires);

        // Record logs to verify events
        vm.recordLogs();

        // Deploy a resolver for the name
        address resolverAddress = registry.deployResolver(label, user);

        // Get the logs
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Verify events were emitted
        bool foundResolverDeployed = false;

        for (uint256 i = 0; i < logs.length; i++) {
            // Check for ResolverDeployed event
            if (logs[i].topics[0] == keccak256("ResolverDeployed(string,address,address)")) {
                foundResolverDeployed = true;
                // The label is indexed, so it's in the topics
                (address resolverAddr, address ownerAddr) = abi.decode(logs[i].data, (address, address));
                assertEq(resolverAddr, resolverAddress);
                assertEq(ownerAddr, user);
            }
        }

        assertTrue(foundResolverDeployed, "ResolverDeployed event not emitted");

        // Verify the resolver was set correctly
        assertEq(registry.getResolver(label), resolverAddress);

        // Verify the resolver is a SingleNameResolver
        SingleNameResolver resolver = SingleNameResolver(resolverAddress);
        assertEq(resolver.owner(), user);

        vm.stopPrank();
    }

    function testSetResolverWithLabel() public {
        vm.startPrank(deployer);

        // Register a name
        string memory label = "example";
        uint64 expires = uint64(block.timestamp + 365 days);
        uint256 roleBitmap = ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY | ROLE_RENEW;
        registry.register(label, user, IRegistry(address(0)), address(0), roleBitmap, expires);

        // Set a resolver for the name
        address resolverAddress = address(0x789);
        registry.setResolver(label, resolverAddress);

        // Verify the resolver was set correctly
        assertEq(registry.getResolver(label), resolverAddress);

        vm.stopPrank();
    }

    function testCalculateNamehash() public {
        vm.startPrank(deployer);

        // Calculate the namehash for a label
        string memory label = "example";
        bytes32 namehash = registry.calculateNamehash(label);

        // Verify the namehash is not zero
        assertTrue(namehash != bytes32(0), "Namehash should not be zero");

        vm.stopPrank();
    }

    function testDeployResolverUnauthorized() public {
        vm.startPrank(user);

        // Register a name
        string memory label = "example";

        // Should revert because caller is not authorized
        vm.expectRevert();
        registry.deployResolver(label, user);

        vm.stopPrank();
    }

    function testDeployResolverNoFactory() public {
        vm.startPrank(deployer);

        // Deploy a new registry without setting the factory
        uint256 deployerRoles = ROLE_ADMIN | ROLE_REGISTRAR | ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY
            | ROLE_SET_TOKEN_OBSERVER | ROLE_RENEW;
        PermissionedRegistryV2 newRegistry =
            new PermissionedRegistryV2(datastore, SimpleRegistryMetadata(address(0)), deployerRoles);

        // Register a name
        string memory label = "example";
        uint64 expires = uint64(block.timestamp + 365 days);
        uint256 roleBitmap = ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY | ROLE_RENEW;
        newRegistry.register(label, user, IRegistry(address(0)), address(0), roleBitmap, expires);

        // Should revert because factory is not set
        vm.expectRevert("Resolver factory not set");
        newRegistry.deployResolver(label, user);

        vm.stopPrank();
    }
}
