// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "../src/registry/PermissionedRegistry.sol";
import "../src/registry/RegistryDatastore.sol";
import "../src/registry/EnhancedAccessControl.sol";
import "../src/registry/SimpleRegistryMetadata.sol";
import "../src/registry/BaseRegistry.sol";

contract TestRootRegistry is Test, ERC1155Holder {
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);
    event URI(string value, uint256 indexed id);
    event NewSubname(uint256 indexed node, string label);

    RegistryDatastore datastore;
    PermissionedRegistry registry;
    SimpleRegistryMetadata metadata;

    uint256 constant ROLE_SET_SUBREGISTRY = 1 << 2;
    uint256 constant ROLE_SET_RESOLVER = 1 << 3;
    uint256 constant ROLE_SET_FLAGS = 1 << 4;
    uint256 constant defaultRoleBitmap = ROLE_SET_SUBREGISTRY | ROLE_SET_RESOLVER | ROLE_SET_FLAGS;
    uint256 constant lockedResolverRoleBitmap = ROLE_SET_SUBREGISTRY | ROLE_SET_FLAGS;
    uint256 constant lockedSubregistryRoleBitmap = ROLE_SET_RESOLVER | ROLE_SET_FLAGS;
    uint256 constant lockedFlagsRoleBitmap = ROLE_SET_SUBREGISTRY | ROLE_SET_RESOLVER;
    uint64 constant MAX_EXPIRY = type(uint64).max;

    address owner = makeAddr("owner");

    function setUp() public {
        datastore = new RegistryDatastore();
        metadata = new SimpleRegistryMetadata();
        registry = new PermissionedRegistry(datastore, metadata);
        metadata.grantRootRoles(metadata.ROLE_UPDATE_METADATA(), address(registry));
    }


    function test_register_unlocked() public {
        uint256 expectedId = uint256(keccak256("test2"));
        uint256 tokenId = registry.register("test2", owner, registry, address(0), 0, defaultRoleBitmap, MAX_EXPIRY, "");
        vm.assertEq(tokenId & ~uint256(registry.FLAGS_MASK()), expectedId & ~uint256(registry.FLAGS_MASK()));
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, owner));
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, owner));
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_FLAGS, owner));
    }

    function test_register_locked_resolver_and_subregistry() public {
        uint256 expectedId = uint256(keccak256("test2"));
        uint256 tokenId = registry.register("test2", owner, registry, address(0), 0, lockedFlagsRoleBitmap, MAX_EXPIRY, "");
        vm.assertEq(tokenId & ~uint256(registry.FLAGS_MASK()), expectedId & ~uint256(registry.FLAGS_MASK()));
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, owner));
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, owner));
        assertFalse(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_FLAGS, owner));
    }

    function test_register_locked_subregistry() public {
        uint256 expectedId = uint256(keccak256("test2"));
        uint256 tokenId = registry.register("test2", owner, registry, address(0), 0, lockedSubregistryRoleBitmap, MAX_EXPIRY, "");
        vm.assertEq(tokenId & ~uint256(registry.FLAGS_MASK()), expectedId & ~uint256(registry.FLAGS_MASK()));
        assertFalse(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, owner));
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, owner));
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_FLAGS, owner));
    }

    function test_register_locked_resolver() public {
        uint256 expectedId = uint256(keccak256("test2"));
        uint256 tokenId = registry.register("test2", owner, registry, address(0), 0, lockedResolverRoleBitmap, MAX_EXPIRY, "");
        vm.assertEq(tokenId & ~uint256(registry.FLAGS_MASK()), expectedId & ~uint256(registry.FLAGS_MASK()));
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, owner));
        assertFalse(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, owner));
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_FLAGS, owner));
    }

    function test_set_subregistry() public {
        uint256 tokenId = registry.register("test", owner, registry, address(0), 0, defaultRoleBitmap, MAX_EXPIRY, "");
        vm.prank(owner);
        registry.setSubregistry(tokenId, IRegistry(address(this)));
        vm.assertEq(address(registry.getSubregistry("test")), address(this));
    }

    function test_Revert_cannot_set_locked_subregistry() public {
        uint256 tokenId = registry.register("test", owner, registry, address(0), 0, lockedSubregistryRoleBitmap, MAX_EXPIRY, "");

        address unauthorizedCaller = address(0xdead);
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, unauthorizedCaller));
        vm.prank(unauthorizedCaller);
        registry.setSubregistry(tokenId, IRegistry(address(this)));
    }

    function test_set_resolver() public {
        uint256 tokenId = registry.register("test", owner, registry, address(0), 0, defaultRoleBitmap, MAX_EXPIRY, "");
        vm.prank(owner);
        registry.setResolver(tokenId, address(this));
        vm.assertEq(address(registry.getResolver("test")), address(this));
    }

    function test_Revert_cannot_set_locked_resolver() public {
        uint256 tokenId = registry.register("test", owner, registry, address(0), 0, lockedResolverRoleBitmap, MAX_EXPIRY, "");

        address unauthorizedCaller = address(0xdead);
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, unauthorizedCaller));
        vm.prank(unauthorizedCaller);
        registry.setResolver(tokenId, address(this));
    }
    
    function test_set_flags() public {
        uint256 tokenId = registry.register("test", owner, registry, address(0), 0, defaultRoleBitmap, MAX_EXPIRY, "");
        uint96 flags = 0x42; // Some arbitrary flags
        vm.prank(owner);
        uint256 newTokenId = registry.setFlags(tokenId, flags);
        (, uint32 actualFlags) = registry.nameData(newTokenId);
        
        // Check the new token ID has the flags
        assertEq(uint32(flags), actualFlags);
        
        // Verify the new token ID incorporates the flags
        assertEq(newTokenId & uint256(registry.FLAGS_MASK()), uint256(flags));
        
        // Make sure base part of token ID is the same
        assertEq(newTokenId & ~uint256(registry.FLAGS_MASK()), tokenId & ~uint256(registry.FLAGS_MASK()));
        
        // Verify ownership of the new token ID
        assertEq(registry.ownerOf(newTokenId), owner);
    }
    
    function test_set_same_flags() public {
        // First register a token with initial flags
        uint96 initialFlags = 0x42;
        uint256 tokenId = registry.register("test", owner, registry, address(0), initialFlags, defaultRoleBitmap, MAX_EXPIRY, "");
        
        // Record logs to verify no minting/burning events
        vm.recordLogs();
        
        // Set the same flags
        vm.prank(owner);
        uint256 newTokenId = registry.setFlags(tokenId, initialFlags);
        
        // Verify token ID hasn't changed
        assertEq(newTokenId, tokenId);
        
        // Check flags remain the same
        (, uint32 actualFlags) = registry.nameData(newTokenId);
        assertEq(uint32(initialFlags), actualFlags);
        
        // Verify no mint/burn events were emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint i = 0; i < logs.length; i++) {
            bytes32 topic0 = logs[i].topics[0];
            assertFalse(
                topic0 == keccak256("TransferSingle(address,address,address,uint256,uint256)"),
                "No transfer events should be emitted when setting the same flags"
            );
        }
    }

    function test_Revert_cannot_set_locked_flags() public {
        uint256 tokenId = registry.register("test", owner, registry, address(0), 0, lockedFlagsRoleBitmap, MAX_EXPIRY, "");

        address unauthorizedCaller = address(0xdead);
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, registry.tokenIdResource(tokenId), ROLE_SET_FLAGS, unauthorizedCaller));
        vm.prank(unauthorizedCaller);
        registry.setFlags(tokenId, 0x1);
    }

    function test_set_uri() public {
        string memory uri = "https://example.com/";
        uint256 tokenId = registry.register("test2", owner, registry, address(0), 0, defaultRoleBitmap, MAX_EXPIRY, uri);
        string memory actualUri = registry.uri(tokenId);
        vm.assertEq(actualUri, uri);
        
        uri = "https://ens.domains/";
        vm.prank(owner);
        registry.setUri(tokenId, uri);
        actualUri = registry.uri(tokenId);
        vm.assertEq(actualUri, uri);
    }

    function test_register() public {
        // Setup test data
        string memory label = "testmint";
        string memory testUri = "https://example.com/testmint";
        uint96 testFlags = 0;
        
        // Start recording logs
        vm.recordLogs();
        
        // Call register function
        vm.prank(address(this));
        uint256 tokenId = registry.register(label, owner, registry, address(0), testFlags, defaultRoleBitmap, MAX_EXPIRY, testUri);
        
        // Get recorded logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Verify token ID calculation
        uint256 expectedId = uint256(keccak256(bytes(label)));
        vm.assertEq(tokenId & ~uint256(registry.FLAGS_MASK()), expectedId & ~uint256(registry.FLAGS_MASK()));
        
        // Verify ownership
        vm.assertEq(registry.ownerOf(tokenId), owner);
        
        // Verify roles were granted
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, owner));
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, owner));
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_FLAGS, owner));
        
        // Verify subregistry was set
        vm.assertEq(address(registry.getSubregistry(label)), address(registry));
        
        // Verify URI was set
        vm.assertEq(registry.uri(tokenId), testUri);
        
        // Verify events - check each log
        bool foundTransferEvent = false;
        bool foundUriEvent = false;
        bool foundNewSubnameEvent = false;
        
        for (uint i = 0; i < logs.length; i++) {
            bytes32 topic0 = logs[i].topics[0];
            
            // TransferSingle event
            if (topic0 == keccak256("TransferSingle(address,address,address,uint256,uint256)")) {
                foundTransferEvent = true;
                address operator = address(uint160(uint256(logs[i].topics[1])));
                address from = address(uint160(uint256(logs[i].topics[2])));
                address to = address(uint160(uint256(logs[i].topics[3])));
                
                // The operator is the caller of the register function, which is this test contract
                assertEq(operator, address(this));
                assertEq(from, address(0));
                assertEq(to, owner);
                
                (uint256 id, uint256 value) = abi.decode(logs[i].data, (uint256, uint256));
                assertEq(id, tokenId);
                assertEq(value, 1);
            }
            // URI event
            else if (topic0 == keccak256("URI(string,uint256)")) {
                foundUriEvent = true;
                assertEq(logs[i].topics.length, 2);
                assertEq(uint256(logs[i].topics[1]), tokenId);
                
                string memory value = abi.decode(logs[i].data, (string));
                assertEq(keccak256(bytes(value)), keccak256(bytes(testUri)));
            }
            // NewSubname event
            else if (topic0 == keccak256("NewSubname(uint256,string)")) {
                foundNewSubnameEvent = true;
                assertEq(logs[i].topics.length, 2);
                assertEq(uint256(logs[i].topics[1]), tokenId);
                
                string memory value = abi.decode(logs[i].data, (string));
                assertEq(keccak256(bytes(value)), keccak256(bytes(label)));
            }
        }
        
        assertTrue(foundTransferEvent, "No TransferSingle event found");
        assertTrue(foundUriEvent, "No URI event found");
        assertTrue(foundNewSubnameEvent, "No NewSubname event found");
    }

    function test_Revert_register_without_permission() public {
        // Setup test data
        string memory label = "testmint";
        string memory testUri = "https://example.com/testmint";
        uint96 testFlags = 0;
        address unauthorizedCaller = makeAddr("unauthorized");
        
        // First, revoke the REGISTRAR role from the test contract
        // since it was granted in the constructor to the deployer (this test contract)
        registry.revokeRootRoles(registry.ROLE_REGISTRAR(), address(this));
        
        // Verify the test contract no longer has the role
        assertFalse(registry.hasRoles(registry.ROOT_RESOURCE(), registry.ROLE_REGISTRAR(), address(this)));
        
        // The test should now fail since no one has permission
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, registry.ROOT_RESOURCE(), registry.ROLE_REGISTRAR(), unauthorizedCaller));
        vm.prank(unauthorizedCaller);
        registry.register(label, owner, registry, address(0), testFlags, defaultRoleBitmap, MAX_EXPIRY, testUri);
    }
}