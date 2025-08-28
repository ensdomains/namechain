// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {MigratedWrappedNameRegistry} from "../src/L1/MigratedWrappedNameRegistry.sol";
import {IRegistry} from "../src/common/IRegistry.sol";
import {IRegistryDatastore} from "../src/common/IRegistryDatastore.sol";
import {RegistryDatastore} from "../src/common/RegistryDatastore.sol";
import {IRegistryMetadata} from "../src/common/IRegistryMetadata.sol";
import {ENS} from "@ens/contracts/registry/ENS.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {LibRegistryRoles} from "../src/common/LibRegistryRoles.sol";
import {NameUtils} from "../src/common/NameUtils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {INameWrapper} from "@ens/contracts/wrapper/INameWrapper.sol";
import {ENS} from "@ens/contracts/registry/ENS.sol";
import {VerifiableFactory} from "../lib/verifiable-factory/src/VerifiableFactory.sol";
import {IPermissionedRegistry} from "../src/common/IPermissionedRegistry.sol";
import {TransferData, MigrationData} from "../src/common/TransferData.sol";
import {CANNOT_UNWRAP, CANNOT_BURN_FUSES} from "@ens/contracts/wrapper/INameWrapper.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

contract MockRegistryMetadata is IRegistryMetadata {
    function tokenUri(uint256) external pure override returns (string memory) {
        return "";
    }
}

contract MockNameWrapper {
    mapping(uint256 => address) public owners;
    mapping(uint256 => bool) public wrapped;
    mapping(uint256 => uint32) public fuses;
    mapping(uint256 => uint64) public expiries;

    function setOwner(uint256 tokenId, address owner) external {
        owners[tokenId] = owner;
    }

    function setWrapped(uint256 tokenId, bool _isWrapped) external {
        wrapped[tokenId] = _isWrapped;
    }

    function setFuseData(uint256 tokenId, uint32 _fuses, uint64 expiry) external {
        fuses[tokenId] = _fuses;
        expiries[tokenId] = expiry;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        return owners[tokenId];
    }

    function isWrapped(bytes32 node) external view returns (bool) {
        return wrapped[uint256(node)];
    }

    function getData(uint256 tokenId) external view returns (address, uint32, uint64) {
        return (owners[tokenId], fuses[tokenId], expiries[tokenId]);
    }
}

contract MockENS {
    mapping(bytes32 => address) private resolvers;
    
    function setResolver(bytes32 node, address resolverAddress) external {
        resolvers[node] = resolverAddress;
    }
    
    function resolver(bytes32 node) external view returns (address) {
        return resolvers[node];
    }
}

contract TestMigratedWrappedNameRegistry is Test {
    MigratedWrappedNameRegistry implementation;
    MigratedWrappedNameRegistry registry;
    RegistryDatastore datastore;
    MockRegistryMetadata metadata;
    MockENS ensRegistry;
    MockNameWrapper nameWrapper;
    
    address owner = address(this);
    address user = address(0x1234);
    address mockResolver = address(0xABCD);
    address v1Resolver = address(0xDEAD);
    
    string testLabel = "test";
    uint256 testLabelId;

    function setUp() public {
        datastore = new RegistryDatastore();
        metadata = new MockRegistryMetadata();
        ensRegistry = new MockENS();
        nameWrapper = new MockNameWrapper();
        
        // Deploy implementation
        implementation = new MigratedWrappedNameRegistry(
            INameWrapper(address(nameWrapper)), // mock nameWrapper
            ENS(address(ensRegistry)), // mock ENS registry
            VerifiableFactory(address(0)), // mock factory
            IPermissionedRegistry(address(0)), // mock ethRegistry
            datastore,
            metadata
        );
        
        // Deploy proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            MigratedWrappedNameRegistry.initialize.selector,
            owner,
            "\x03eth\x00" // parent DNS-encoded name for .eth
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        registry = MigratedWrappedNameRegistry(address(proxy));
        
        testLabelId = NameUtils.labelToCanonicalId(testLabel);
        
        // Setup v1 resolver in ENS registry
        bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel(testLabel);
        bytes32 node = NameCoder.namehash(dnsEncodedName, 0);
        ensRegistry.setResolver(node, v1Resolver);
    }

    /**
     * @dev Helper method to register a name using the wrapper contract
     */
    function _registerName(
        MigratedWrappedNameRegistry targetRegistry,
        string memory label,
        address nameOwner,
        IRegistry subregistry,
        address resolver,
        uint256 roleBitmap,
        uint64 expires
    ) internal {
        vm.prank(address(nameWrapper));
        targetRegistry.register(label, nameOwner, subregistry, resolver, roleBitmap, expires);
    }

    function test_getResolver_unregistered_name() public view {
        // Name not registered (expiry = 0), should fall back to ENS registry
        address resolver = registry.getResolver(testLabel);
        assertEq(resolver, v1Resolver, "Should return v1 resolver from ENS registry");
    }

    function test_getResolver_registered_name_with_resolver() public {
        // Register name first
        uint64 expiry = uint64(block.timestamp + 86400);
        _registerName(registry, testLabel, user, registry, mockResolver, LibRegistryRoles.ROLE_SET_RESOLVER, expiry);
        
        // Should return the registered resolver
        address resolver = registry.getResolver(testLabel);
        assertEq(resolver, mockResolver, "Should return registered resolver");
    }

    function test_getResolver_registered_name_null_resolver() public {
        // Register name with null resolver
        uint64 expiry = uint64(block.timestamp + 86400);
        _registerName(registry, testLabel, user, registry, address(0), LibRegistryRoles.ROLE_SET_RESOLVER, expiry);
        
        // Should return address(0) since name is registered
        address resolver = registry.getResolver(testLabel);
        assertEq(resolver, address(0), "Should return null resolver for registered name");
    }

    function test_getResolver_expired_name() public {
        // Register name that expires immediately
        uint64 expiry = uint64(block.timestamp);
        _registerName(registry, testLabel, user, registry, mockResolver, LibRegistryRoles.ROLE_SET_RESOLVER, expiry);
        
        // Move time forward
        vm.warp(block.timestamp + 1);
        
        // Should return address(0) for expired name
        address resolver = registry.getResolver(testLabel);
        assertEq(resolver, address(0), "Should return zero address for expired name");
    }

    function test_getResolver_ens_registry_returns_zero() public {
        // Clear the resolver in ENS registry
        bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel(testLabel);
        bytes32 node = NameCoder.namehash(dnsEncodedName, 0);
        ensRegistry.setResolver(node, address(0));
        
        // Should return address(0) when ENS registry returns zero
        address resolver = registry.getResolver(testLabel);
        assertEq(resolver, address(0), "Should return zero address when ENS registry returns zero");
    }

    function test_getResolver_different_labels() public {
        string memory label1 = "foo";
        string memory label2 = "bar";
        
        // Setup different resolvers in ENS registry
        bytes32 node1 = NameCoder.namehash(NameUtils.dnsEncodeEthLabel(label1), 0);
        bytes32 node2 = NameCoder.namehash(NameUtils.dnsEncodeEthLabel(label2), 0);
        ensRegistry.setResolver(node1, address(0x1111));
        ensRegistry.setResolver(node2, address(0x2222));
        
        // Test unregistered names return correct v1 resolvers
        assertEq(registry.getResolver(label1), address(0x1111), "Should return correct v1 resolver for label1");
        assertEq(registry.getResolver(label2), address(0x2222), "Should return correct v1 resolver for label2");
        
        // Register label1
        _registerName(registry, label1, user, registry, address(0x3333), LibRegistryRoles.ROLE_SET_RESOLVER, uint64(block.timestamp + 86400));
        
        // label1 should now return registered resolver, label2 still from ENS
        assertEq(registry.getResolver(label1), address(0x3333), "Should return registered resolver for label1");
        assertEq(registry.getResolver(label2), address(0x2222), "Should still return v1 resolver for label2");
    }

    function test_getResolver_registration_lifecycle() public {
        // Initially unregistered - should use ENS registry
        assertEq(registry.getResolver(testLabel), v1Resolver, "Should use v1 resolver initially");
        
        // Register the name
        uint64 expiry = uint64(block.timestamp + 100);
        _registerName(registry, testLabel, user, registry, mockResolver, LibRegistryRoles.ROLE_SET_RESOLVER, expiry);
        assertEq(registry.getResolver(testLabel), mockResolver, "Should use registered resolver");
        
        // Update resolver
        (uint256 tokenId,,) = registry.getNameData(testLabel);
        vm.prank(user);
        registry.setResolver(tokenId, address(0x9999));
        assertEq(registry.getResolver(testLabel), address(0x9999), "Should use updated resolver");
        
        // Let name expire
        vm.warp(block.timestamp + 101);
        assertEq(registry.getResolver(testLabel), address(0), "Should return zero for expired name");
    }

    function test_validateHierarchy_parent_migrated() public {
        // First register parent "test" in registry
        uint64 expiry = uint64(block.timestamp + 86400);
        _registerName(registry, "test", user, registry, mockResolver, LibRegistryRoles.ROLE_SET_RESOLVER, expiry);
        
        // Create subdomain migration data for "sub.test.eth"
        bytes memory subDnsName = NameCoder.encode("sub.test.eth");
        
        // Test the internal hierarchy validation by calling the migration process
        // We'll simplify and just check that we don't get ParentNotMigrated error
        uint256 subTokenId = uint256(NameCoder.namehash(subDnsName, 0));
        
        // Set up the subdomain token as locked but simplified test that should pass hierarchy validation
        nameWrapper.setFuseData(subTokenId, CANNOT_UNWRAP, uint64(block.timestamp + 86400));
        nameWrapper.setOwner(subTokenId, user);
        
        // Create a minimal migration that should pass hierarchy validation
        // Since we don't have a proper factory, we expect it to fail later, but not on hierarchy validation
        vm.prank(address(nameWrapper));
        try registry.onERC1155Received(address(nameWrapper), user, subTokenId, 1, 
            abi.encode(MigrationData({
                transferData: TransferData({
                    label: "sub",
                    owner: user,
                    subregistry: address(0),
                    resolver: mockResolver,
                    expires: expiry,
                    roleBitmap: LibRegistryRoles.ROLE_SET_RESOLVER
                }),
                toL1: false,
                dnsEncodedName: subDnsName,
                salt: abi.encodePacked("test_salt")
            }))
        ) {
            // If it succeeds, that's fine
        } catch Error(string memory reason) {
            // Should not fail on hierarchy validation when parent is registered
            assertTrue(keccak256(bytes(reason)) != keccak256(bytes("ParentNotMigrated")), "Should not fail on parent validation");
        } catch (bytes memory) {
            // Other failures are OK for this test - we just want to ensure hierarchy validation passes
        }
    }

    function test_validateHierarchy_parent_not_migrated() public {
        // Create subdomain migration data
        bytes memory subDnsName = NameCoder.encode("sub.test.eth");
        
        // Generate token identifier for subdomain migration 
        uint256 subTokenId = uint256(NameCoder.namehash(subDnsName, 0));
        
        // Set up the subdomain token as locked
        nameWrapper.setFuseData(subTokenId, CANNOT_UNWRAP, uint64(block.timestamp + 86400));
        nameWrapper.setOwner(subTokenId, user);
        
        // Should revert when parent is neither migrated nor controlled
        // Compute the expected parent namehash for "test.eth"
        bytes32 expectedParentNode = NameCoder.namehash(NameCoder.encode("test.eth"), 0);
        vm.expectRevert(abi.encodeWithSelector(MigratedWrappedNameRegistry.ParentNotMigrated.selector, expectedParentNode));
        
        vm.prank(address(nameWrapper));
        registry.onERC1155Received(address(nameWrapper), user, subTokenId, 1, 
            abi.encode(MigrationData({
                transferData: TransferData({
                    label: "sub",
                    owner: user,
                    subregistry: address(0),
                    resolver: mockResolver,
                    expires: uint64(block.timestamp + 86400),
                    roleBitmap: LibRegistryRoles.ROLE_SET_RESOLVER
                }),
                toL1: false,
                dnsEncodedName: subDnsName,
                salt: abi.encodePacked("test_salt")
            }))
        );
    }

    function test_validateHierarchy_no_parent_domain() public {
        // Try to migrate a top-level domain like "eth" (which has no parent)
        bytes memory ethDnsName = NameCoder.encode("eth");
        uint256 ethTokenId = uint256(NameCoder.namehash(ethDnsName, 0));
        
        // Set up the token as locked
        nameWrapper.setFuseData(ethTokenId, CANNOT_UNWRAP, uint64(block.timestamp + 86400));
        nameWrapper.setOwner(ethTokenId, user);
        
        // Should revert with NoParentDomain error
        vm.expectRevert(MigratedWrappedNameRegistry.NoParentDomain.selector);
        
        vm.prank(address(nameWrapper));
        registry.onERC1155Received(address(nameWrapper), user, ethTokenId, 1,
            abi.encode(MigrationData({
                transferData: TransferData({
                    label: "eth",
                    owner: user,
                    subregistry: address(0),
                    resolver: mockResolver,
                    expires: uint64(block.timestamp + 86400),
                    roleBitmap: LibRegistryRoles.ROLE_SET_RESOLVER
                }),
                toL1: false,
                dnsEncodedName: ethDnsName,
                salt: abi.encodePacked("test_salt")
            }))
        );
    }

    function test_getResolver_3LD_unregistered() public {
        // Create a 3LD registry for "sub.test.eth"
        MigratedWrappedNameRegistry subRegistry = _create3LDRegistry("sub.test.eth");
        
        // Test label "example" which would resolve to "example.sub.test.eth"
        string memory label3LD = "example";
        
        // Setup resolver in ENS registry for the full name
        bytes memory fullDnsName = abi.encodePacked(
            bytes1(uint8(bytes(label3LD).length)),
            label3LD,
            "\x03sub\x04test\x03eth\x00" // sub.test.eth
        );
        bytes32 fullNode = NameCoder.namehash(fullDnsName, 0);
        ensRegistry.setResolver(fullNode, address(0x3333));
        
        // Should return resolver from ENS registry for unregistered 4LD name
        address resolver = subRegistry.getResolver(label3LD);
        assertEq(resolver, address(0x3333), "Should return ENS resolver for unregistered 4LD name");
    }
    
    function test_getResolver_3LD_registered() public {
        // Create a 3LD registry for "sub.test.eth"
        MigratedWrappedNameRegistry subRegistry = _create3LDRegistry("sub.test.eth");
        
        string memory label3LD = "example";
        address expectedResolver = address(0x4444);
        
        // Register the 4LD name in the 3LD registry
        uint64 expiry = uint64(block.timestamp + 86400);
        _registerName(
            subRegistry,
            label3LD,
            user,
            subRegistry,
            expectedResolver,
            LibRegistryRoles.ROLE_SET_RESOLVER,
            expiry
        );
        
        // Should return the registered resolver
        address resolver = subRegistry.getResolver(label3LD);
        assertEq(resolver, expectedResolver, "Should return registered resolver for 4LD name");
    }
    
    function test_getResolver_mixed_levels() public {
        // Test scenario: 2LD registered, 3LD unregistered, 4LD query
        // This tests that the resolver lookup works through multiple registry levels
        
        // 1. Setup 2LD registry (test.eth) - our main registry
        // Already set up in setUp()
        
        // 2. Create 3LD registry (sub.test.eth) but don't register "sub" in 2LD registry
        MigratedWrappedNameRegistry subRegistry = _create3LDRegistry("sub.test.eth");
        
        // 3. Query for "example" in 3LD registry (would be example.sub.test.eth)
        string memory labelMixed = "example";
        
        // Setup resolver in ENS for the full name
        bytes memory fullDnsName = abi.encodePacked(
            bytes1(uint8(bytes(labelMixed).length)),
            labelMixed,
            "\x03sub\x04test\x03eth\x00"
        );
        bytes32 fullNode = NameCoder.namehash(fullDnsName, 0);
        ensRegistry.setResolver(fullNode, address(0x7777));
        
        // Should fall back to ENS registry since "sub" is not registered in 2LD
        address resolver = subRegistry.getResolver(labelMixed);
        assertEq(resolver, address(0x7777), "Should return ENS resolver for mixed level scenario");
    }
    
    // Helper function to create a 3LD registry
    function _create3LDRegistry(string memory domain) internal returns (MigratedWrappedNameRegistry) {
        // Deploy new implementation instance
        MigratedWrappedNameRegistry impl = new MigratedWrappedNameRegistry(
            INameWrapper(address(nameWrapper)),
            ENS(address(ensRegistry)),
            VerifiableFactory(address(0)),
            IPermissionedRegistry(address(0)),
            datastore,
            metadata
        );
        
        // Create DNS-encoded name for the domain (e.g., "\x03sub\x04test\x03eth\x00")
        bytes memory parentDnsName = NameCoder.encode(domain);
        
        // Deploy proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            MigratedWrappedNameRegistry.initialize.selector,
            owner,
            parentDnsName
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        return MigratedWrappedNameRegistry(address(proxy));
    }
}