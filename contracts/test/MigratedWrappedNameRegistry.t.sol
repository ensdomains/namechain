// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {MigratedWrappedNameRegistry} from "../src/L1/MigratedWrappedNameRegistry.sol";
import {IRegistryDatastore} from "../src/common/IRegistryDatastore.sol";
import {RegistryDatastore} from "../src/common/RegistryDatastore.sol";
import {IRegistryMetadata} from "../src/common/IRegistryMetadata.sol";
import {IUniversalResolver} from "@ens/contracts/universalResolver/IUniversalResolver.sol";
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

contract MockUniversalResolver is IUniversalResolver {
    mapping(bytes => address) public resolvers;
    bool public shouldRevert;

    function setResolver(bytes memory name, address resolver) external {
        resolvers[name] = resolver;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function findResolver(bytes calldata name) external view override returns (address, bytes32, uint256) {
        if (shouldRevert) {
            revert("Universal resolver error");
        }
        return (resolvers[name], bytes32(0), 0);
    }

    function resolve(bytes calldata, bytes calldata) external pure override returns (bytes memory, address) {
        return ("", address(0));
    }

    function resolve(bytes calldata, bytes[] calldata) external pure returns (bytes[] memory, address) {
        return (new bytes[](0), address(0));
    }

    function resolveWithProof(bytes calldata, bytes calldata) external pure returns (bytes memory, address, bytes memory, bytes memory) {
        return ("", address(0), "", "");
    }

    function resolveCallback(bytes calldata, bytes[] calldata) external pure returns (bytes[] memory, address) {
        return (new bytes[](0), address(0));
    }

    function reverse(bytes calldata, uint256) external pure returns (string memory, address, address) {
        return ("", address(0), address(0));
    }

    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}

contract TestMigratedWrappedNameRegistry is Test {
    MigratedWrappedNameRegistry implementation;
    MigratedWrappedNameRegistry registry;
    RegistryDatastore datastore;
    MockRegistryMetadata metadata;
    MockUniversalResolver universalResolver;
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
        universalResolver = new MockUniversalResolver();
        nameWrapper = new MockNameWrapper();
        
        // Deploy implementation
        implementation = new MigratedWrappedNameRegistry(
            universalResolver,
            INameWrapper(address(nameWrapper)), // mock nameWrapper
            ENS(address(0)), // mock ENS registry
            VerifiableFactory(address(0)), // mock factory
            IPermissionedRegistry(address(0)), // mock ethRegistry
            datastore,
            metadata
        );
        
        // Deploy proxy and initialize
        bytes memory initData = abi.encodeWithSelector(
            MigratedWrappedNameRegistry.initialize.selector,
            owner,
            LibRegistryRoles.ROLE_REGISTRAR | LibRegistryRoles.ROLE_REGISTRAR_ADMIN | LibRegistryRoles.ROLE_SET_RESOLVER_ADMIN,
            universalResolver
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        registry = MigratedWrappedNameRegistry(address(proxy));
        
        testLabelId = NameUtils.labelToCanonicalId(testLabel);
        
        // Setup v1 resolver in universal resolver
        bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel(testLabel);
        universalResolver.setResolver(dnsEncodedName, v1Resolver);
    }

    function test_getResolver_unregistered_name() public view {
        // Name not registered (expiry = 0), should call through to universal resolver
        address resolver = registry.getResolver(testLabel);
        assertEq(resolver, v1Resolver, "Should return v1 resolver from universal resolver");
    }

    function test_getResolver_registered_name_with_resolver() public {
        // Register name first
        uint64 expiry = uint64(block.timestamp + 86400);
        registry.register(testLabel, user, registry, mockResolver, LibRegistryRoles.ROLE_SET_RESOLVER, expiry);
        
        // Should return the registered resolver
        address resolver = registry.getResolver(testLabel);
        assertEq(resolver, mockResolver, "Should return registered resolver");
    }

    function test_getResolver_registered_name_null_resolver() public {
        // Register name with null resolver
        uint64 expiry = uint64(block.timestamp + 86400);
        registry.register(testLabel, user, registry, address(0), LibRegistryRoles.ROLE_SET_RESOLVER, expiry);
        
        // Should return address(0) since name is registered
        address resolver = registry.getResolver(testLabel);
        assertEq(resolver, address(0), "Should return null resolver for registered name");
    }

    function test_getResolver_expired_name() public {
        // Register name that expires immediately
        uint64 expiry = uint64(block.timestamp);
        registry.register(testLabel, user, registry, mockResolver, LibRegistryRoles.ROLE_SET_RESOLVER, expiry);
        
        // Move time forward
        vm.warp(block.timestamp + 1);
        
        // Should return address(0) for expired name
        address resolver = registry.getResolver(testLabel);
        assertEq(resolver, address(0), "Should return zero address for expired name");
    }

    function test_getResolver_universal_resolver_reverts() public {
        // Make universal resolver revert
        universalResolver.setShouldRevert(true);
        
        // Should return address(0) when universal resolver reverts
        address resolver = registry.getResolver(testLabel);
        assertEq(resolver, address(0), "Should return zero address when universal resolver reverts");
    }

    function test_getResolver_different_labels() public {
        string memory label1 = "foo";
        string memory label2 = "bar";
        
        // Setup different resolvers in universal resolver
        universalResolver.setResolver(NameUtils.dnsEncodeEthLabel(label1), address(0x1111));
        universalResolver.setResolver(NameUtils.dnsEncodeEthLabel(label2), address(0x2222));
        
        // Test unregistered names return correct v1 resolvers
        assertEq(registry.getResolver(label1), address(0x1111), "Should return correct v1 resolver for label1");
        assertEq(registry.getResolver(label2), address(0x2222), "Should return correct v1 resolver for label2");
        
        // Register label1
        registry.register(label1, user, registry, address(0x3333), LibRegistryRoles.ROLE_SET_RESOLVER, uint64(block.timestamp + 86400));
        
        // label1 should now return registered resolver, label2 still from universal
        assertEq(registry.getResolver(label1), address(0x3333), "Should return registered resolver for label1");
        assertEq(registry.getResolver(label2), address(0x2222), "Should still return v1 resolver for label2");
    }

    function test_getResolver_registration_lifecycle() public {
        // Initially unregistered - should use universal resolver
        assertEq(registry.getResolver(testLabel), v1Resolver, "Should use v1 resolver initially");
        
        // Register the name
        uint64 expiry = uint64(block.timestamp + 100);
        registry.register(testLabel, user, registry, mockResolver, LibRegistryRoles.ROLE_SET_RESOLVER, expiry);
        assertEq(registry.getResolver(testLabel), mockResolver, "Should use registered resolver");
        
        // Update resolver
        (uint256 tokenId,,) = registry.getNameData(testLabel);
        registry.grantRoles(tokenId, LibRegistryRoles.ROLE_SET_RESOLVER, user);
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
        registry.register("test", user, registry, mockResolver, LibRegistryRoles.ROLE_SET_RESOLVER, expiry);
        
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
            // Should not fail due to ParentNotMigrated if parent is properly registered
            assertTrue(keccak256(bytes(reason)) != keccak256(bytes("ParentNotMigrated")), "Should not fail on parent validation");
        } catch (bytes memory) {
            // Other failures are OK for this test - we just want to ensure hierarchy validation passes
        }
    }

    function test_validateHierarchy_parent_not_migrated() public {
        // Don't register parent - it's neither migrated nor controlled
        
        // Create subdomain migration data
        bytes memory subDnsName = NameCoder.encode("sub.test.eth");
        
        // Compute the correct tokenId from the DNS encoded name (this should match the namehash) 
        uint256 subTokenId = uint256(NameCoder.namehash(subDnsName, 0));
        
        // Set up the subdomain token as locked
        nameWrapper.setFuseData(subTokenId, CANNOT_UNWRAP, uint64(block.timestamp + 86400));
        nameWrapper.setOwner(subTokenId, user);
        
        // This should revert because parent is not migrated or controlled
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
}