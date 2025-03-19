// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "src/registry/RootRegistry.sol";
import "src/registry/RegistryDatastore.sol";
import "src/registry/Roles.sol";
import "src/registry/EnhancedAccessControl.sol";

contract TestRootRegistry is Test, ERC1155Holder, Roles {
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);

    RegistryDatastore datastore;
    RootRegistry registry;

    uint256 defaultRoleBitmap = ROLE_SET_SUBREGISTRY | ROLE_SET_RESOLVER;
    uint256 lockedResolverRoleBitmap = ROLE_SET_SUBREGISTRY;
    uint256 lockedSubregistryRoleBitmap = ROLE_SET_RESOLVER;

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
}
