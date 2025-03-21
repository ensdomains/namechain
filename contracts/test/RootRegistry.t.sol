// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "../src/registry/RootRegistry.sol";
import "../src/registry/RegistryDatastore.sol";
import "../src/registry/EnhancedAccessControl.sol";

contract TestRootRegistry is Test, ERC1155Holder {
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);
    event URI(string value, uint256 indexed id);
    event NewSubname(uint256 indexed node, string label);

    RegistryDatastore datastore;
    RootRegistry registry;

    uint256 constant ROLE_SET_SUBREGISTRY = 1 << 0;
    uint256 constant ROLE_SET_RESOLVER = 1 << 1;
    uint256 constant defaultRoleBitmap = ROLE_SET_SUBREGISTRY | ROLE_SET_RESOLVER;
    uint256 constant lockedResolverRoleBitmap = ROLE_SET_SUBREGISTRY;
    uint256 constant lockedSubregistryRoleBitmap = ROLE_SET_RESOLVER;

    address owner = makeAddr("owner");

    function setUp() public {
        datastore = new RegistryDatastore();
        registry = new RootRegistry(datastore);
    }


    function test_register_unlocked() public {
        uint256 expectedId = uint256(keccak256("test2"));
        uint256 tokenId = registry.mint("test2", owner, registry, 0, defaultRoleBitmap, "");
        vm.assertEq(tokenId, expectedId);
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, owner));
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, owner));
    }

    function test_register_locked_resolver_and_subregistry() public {
        uint256 expectedId = uint256(keccak256("test2"));
        uint256 tokenId = registry.mint("test2", owner, registry, 0, 0, "");
        vm.assertEq(tokenId, expectedId);
        assertFalse(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, owner));
        assertFalse(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, owner));
    }

    function test_register_locked_subregistry() public {
        uint256 expectedId = uint256(keccak256("test2"));
        uint256 tokenId = registry.mint("test2", owner, registry, 0, lockedSubregistryRoleBitmap, "");
        vm.assertEq(tokenId, expectedId);
        assertFalse(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, owner));
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, owner));
    }

    function test_register_locked_resolver() public {
        uint256 expectedId = uint256(keccak256("test2"));
        uint256 tokenId = registry.mint("test2", owner, registry, 0, lockedResolverRoleBitmap, "");
        vm.assertEq(tokenId, expectedId);
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, owner));
        assertFalse(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, owner));
    }

    function test_set_subregistry() public {
        uint256 tokenId = registry.mint("test", owner, registry, 0, defaultRoleBitmap, "");
        vm.prank(owner);
        registry.setSubregistry(tokenId, IRegistry(address(this)));
        vm.assertEq(address(registry.getSubregistry("test")), address(this));
    }

    function test_Revert_cannot_set_locked_subregistry() public {
        uint256 tokenId = registry.mint("test", owner, registry, 0, lockedSubregistryRoleBitmap, "");

        address unauthorizedCaller = address(0xdead);
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, unauthorizedCaller));
        vm.prank(unauthorizedCaller);
        registry.setSubregistry(tokenId, IRegistry(address(this)));
    }

    function test_set_resolver() public {
        uint256 tokenId = registry.mint("test", owner, registry, 0, defaultRoleBitmap, "");
        vm.prank(owner);
        registry.setResolver(tokenId, address(this));
        vm.assertEq(address(registry.getResolver("test")), address(this));
    }

    function test_Revert_cannot_set_locked_resolver() public {
        uint256 tokenId = registry.mint("test", owner, registry, 0, lockedResolverRoleBitmap, "");

        address unauthorizedCaller = address(0xdead);
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, unauthorizedCaller));
        vm.prank(unauthorizedCaller);
        registry.setResolver(tokenId, address(this));
    }

    function test_Revert_cannot_set_locked_flags() public {
        uint96 flags = registry.FLAG_FLAGS_LOCKED();
        uint256 tokenId = registry.mint("test", owner, registry, flags, defaultRoleBitmap, "");

        vm.expectRevert(abi.encodeWithSelector(BaseRegistry.InvalidSubregistryFlags.selector, tokenId, registry.FLAG_FLAGS_LOCKED(), 0));
        vm.prank(owner);
        registry.setFlags(tokenId, flags);
    }

    function test_set_uri() public {
        string memory uri = "https://example.com/";
        uint256 tokenId = registry.mint("test2", owner, registry, 0, defaultRoleBitmap, uri);
        string memory actualUri = registry.uri(tokenId);
        vm.assertEq(actualUri, uri);
        
        uri = "https://ens.domains/";
        vm.prank(owner);
        registry.setUri(tokenId, uri);
        actualUri = registry.uri(tokenId);
        vm.assertEq(actualUri, uri);
    }

    // function test_Revert_cannot_set_unauthorized_uri() public {
    //     string memory uri = "https://example.com/";
    //     uint256 tokenId = registry.mint("test2", address(registry), registry, 0, uri);
    //     string memory actualUri = registry.uri(tokenId);
    //     vm.assertEq(actualUri, uri);
        
    //     uri = "https://ens.domains/";
    //     registry.setUri(tokenId, uri);
    // }

    function test_mint() public {
        // Setup test data
        string memory label = "testmint";
        string memory testUri = "https://example.com/testmint";
        uint96 testFlags = 0;
        
        // Start recording logs
        vm.recordLogs();
        
        // Call mint function
        vm.prank(address(this));
        uint256 tokenId = registry.mint(label, owner, registry, testFlags, defaultRoleBitmap, testUri);
        
        // Get recorded logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        
        // Verify token ID calculation
        uint256 expectedId = uint256(keccak256(bytes(label)));
        vm.assertEq(tokenId, expectedId);
        
        // Verify ownership
        vm.assertEq(registry.ownerOf(tokenId), owner);
        
        // Verify roles were granted
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, owner));
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, owner));
        
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
                
                // The operator is the caller of the mint function, which is this test contract
                assertEq(operator, address(this));
                assertEq(from, address(0));
                assertEq(to, owner);
                
                (uint256 id, uint256 value) = abi.decode(logs[i].data, (uint256, uint256));
                assertEq(id, expectedId);
                assertEq(value, 1);
            }
            // URI event
            else if (topic0 == keccak256("URI(string,uint256)")) {
                foundUriEvent = true;
                assertEq(logs[i].topics.length, 2);
                assertEq(uint256(logs[i].topics[1]), expectedId);
                
                string memory value = abi.decode(logs[i].data, (string));
                assertEq(keccak256(bytes(value)), keccak256(bytes(testUri)));
            }
            // NewSubname event
            else if (topic0 == keccak256("NewSubname(uint256,string)")) {
                foundNewSubnameEvent = true;
                assertEq(logs[i].topics.length, 2);
                assertEq(uint256(logs[i].topics[1]), expectedId);
                
                string memory value = abi.decode(logs[i].data, (string));
                assertEq(keccak256(bytes(value)), keccak256(bytes(label)));
            }
        }
        
        assertTrue(foundTransferEvent, "No TransferSingle event found");
        assertTrue(foundUriEvent, "No URI event found");
        assertTrue(foundNewSubnameEvent, "No NewSubname event found");
    }

    function test_Revert_mint_without_permission() public {
        // Setup test data
        string memory label = "testmint";
        string memory testUri = "https://example.com/testmint";
        uint96 testFlags = 0;
        address unauthorizedCaller = makeAddr("unauthorized");
        
        // First, revoke the TLD_ISSUER role from the test contract
        // since it was granted in the constructor to the deployer (this test contract)
        registry.revokeRoles(registry.ROOT_RESOURCE(), registry.ROLE_TLD_ISSUER(), address(this));
        
        // Verify the test contract no longer has the role
        assertFalse(registry.hasRoles(registry.ROOT_RESOURCE(), registry.ROLE_TLD_ISSUER(), address(this)));
        
        // The test should now fail since no one has permission
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, registry.ROOT_RESOURCE(), registry.ROLE_TLD_ISSUER(), unauthorizedCaller));
        vm.prank(unauthorizedCaller);
        registry.mint(label, owner, registry, testFlags, defaultRoleBitmap, testUri);
    }
}
