// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "../src/registry/PermissionedRegistry.sol";
import "../src/registry/RegistryDatastore.sol";
import "../src/registry/IRegistryMetadata.sol";
import "../src/registry/SimpleRegistryMetadata.sol";
import "../src/registry/BaseRegistry.sol";
import "../src/registry/IPermissionedRegistry.sol";
import "../src/registry/ETHRegistrar.sol";
import "../src/registry/IPriceOracle.sol";


contract TestPermissionedRegistry is Test, ERC1155Holder {
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);

    RegistryDatastore datastore;
    PermissionedRegistry registry;
    ETHRegistrar registrar;
    MockTokenObserver observer;
    RevertingTokenObserver revertingObserver;
    IRegistryMetadata metadata;
    MockPriceOracle priceOracle;

    // Role bitmaps for different permission configurations
    uint256 constant ROLE_REGISTRAR = 1 << 0;
    uint256 constant ROLE_REGISTRAR_ADMIN = ROLE_REGISTRAR << 128;
    uint256 constant ROLE_RENEW = 1 << 1;
    uint256 constant ROLE_RENEW_ADMIN = ROLE_RENEW << 128;
    uint256 constant ROLE_SET_SUBREGISTRY = 1 << 2;
    uint256 constant ROLE_SET_RESOLVER = 1 << 3;
    uint256 constant ROLE_SET_TOKEN_OBSERVER = 1 << 4;
    uint256 constant defaultRoleBitmap = ROLE_SET_SUBREGISTRY | ROLE_SET_RESOLVER | ROLE_SET_TOKEN_OBSERVER;
    uint256 constant lockedResolverRoleBitmap = ROLE_SET_SUBREGISTRY | ROLE_SET_TOKEN_OBSERVER;
    uint256 constant lockedSubregistryRoleBitmap = ROLE_SET_RESOLVER | ROLE_SET_TOKEN_OBSERVER;
    uint256 constant noRolesRoleBitmap = 0;
    
    address owner = makeAddr("owner");
    address user1 = makeAddr("user1");

    function setUp() public {
        datastore = new RegistryDatastore();
        metadata = new SimpleRegistryMetadata();
        registry = new PermissionedRegistry(datastore, metadata);
        registry.grantRootRoles(ROLE_REGISTRAR, address(this));
        observer = new MockTokenObserver();
        revertingObserver = new RevertingTokenObserver();
        priceOracle = new MockPriceOracle();
        registrar = new ETHRegistrar(address(registry), priceOracle, 60, 86400);
    }

    function test_constructor_sets_roles() public view {
        uint256 r = ROLE_REGISTRAR | ROLE_REGISTRAR_ADMIN | ROLE_RENEW | ROLE_RENEW_ADMIN;
        assertTrue(registry.hasRoles(registry.ROOT_RESOURCE(), r, address(this)));
    }

    function test_Revert_register_without_registrar_role() public {
        address nonRegistrar = makeAddr("nonRegistrar");

        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, registry.ROOT_RESOURCE(), ROLE_REGISTRAR, nonRegistrar));
        vm.prank(nonRegistrar);
        registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 86400);
    }

    function test_Revert_renew_without_renew_role() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 86400);
        
        address nonRenewer = makeAddr("nonRenewer");

        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, registry.tokenIdResource(tokenId), ROLE_RENEW, nonRenewer));
        vm.prank(nonRenewer);
        registry.renew(tokenId, uint64(block.timestamp) + 172800);
    }

    function test_token_specific_renewer_can_renew() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 86400);
        
        address tokenRenewer = makeAddr("tokenRenewer");
        
        // Grant the RENEW role specifically for this token
        registry.grantRoles(registry.tokenIdResource(tokenId), ROLE_RENEW, tokenRenewer);
        
        // Verify the role was granted
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_RENEW, tokenRenewer));
        
        // This user doesn't have the ROOT_RESOURCE ROLE_RENEW
        assertFalse(registry.hasRoles(registry.ROOT_RESOURCE(), ROLE_RENEW, tokenRenewer));
        
        // But should still be able to renew this specific token
        vm.prank(tokenRenewer);
        uint64 newExpiry = uint64(block.timestamp) + 172800;
        registry.renew(tokenId, newExpiry);
        
        uint64 expiry = registry.getExpiry(tokenId);    
        assertEq(expiry, newExpiry);
    }

    function test_token_owner_can_renew_if_granted_role() public {
        // Register a token with specific roles including ROLE_RENEW
        uint256 roleBitmap = defaultRoleBitmap | ROLE_RENEW;
        uint256 tokenId = registry.register("test2", user1, registry, address(0), roleBitmap, uint64(block.timestamp) + 86400);
        
        // Verify the owner has the RENEW role for this token
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_RENEW, user1));
        
        // Owner should be able to renew their own token
        vm.prank(user1);
        uint64 newExpiry = uint64(block.timestamp) + 172800;
        registry.renew(tokenId, newExpiry);
        
        uint64 expiry = registry.getExpiry(tokenId);
        assertEq(expiry, newExpiry);
    }

    function test_Revert_owner_cannot_renew_without_role() public {
        // First create a user without global renew permissions
        address tokenOwner = makeAddr("tokenOwner");
        
        // Register a token with NO roles granted to the owner
        uint256 tokenId = registry.register("test2", tokenOwner, registry, address(0), noRolesRoleBitmap, uint64(block.timestamp) + 86400);
        
        // Verify the owner doesn't have the RENEW role for this token (this is the intent of the test)
        assertFalse(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_RENEW, tokenOwner));
        
        // Owner should not be able to renew without the role
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, registry.tokenIdResource(tokenId), ROLE_RENEW, tokenOwner));
        vm.prank(tokenOwner);
        registry.renew(tokenId, uint64(block.timestamp) + 172800);
    }

    function test_registrar_can_register() public {
        address registrar2 = makeAddr("registrar");
        registry.grantRootRoles(ROLE_REGISTRAR, registrar2);
        
        vm.prank(registrar2);
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 86400);
        assertEq(registry.ownerOf(tokenId), address(this));
    }

    function test_renewer_can_renew() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 86400);
        
        address renewer = makeAddr("renewer");
        registry.grantRootRoles(ROLE_RENEW, renewer);
        
        vm.prank(renewer);
        uint64 newExpiry = uint64(block.timestamp) + 172800;
        registry.renew(tokenId, newExpiry);
        
        uint64 expiry = registry.getExpiry(tokenId);
        assertEq(expiry, newExpiry);
    }

    function _expectedId(string memory label) internal pure returns (uint256) {
        return uint256(keccak256(bytes(label)));
    }

    function test_register_unlocked() public {
        uint256 expectedId = _expectedId("test2");

        uint256 tokenId = registry.register("test2", owner, registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 86400);
        vm.assertEq(tokenId, expectedId);
        
        // Verify roles
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, owner));
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, owner));
    }

    function test_register_locked() public {
        uint256 expectedId = _expectedId("test2");

        uint256 tokenId = registry.register("test2", owner, registry, address(0), noRolesRoleBitmap, uint64(block.timestamp) + 86400);
        vm.assertEq(tokenId, expectedId);
        
        // Verify roles
        assertFalse(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, owner));
        assertFalse(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, owner));
    }

    function test_register_locked_subregistry() public {
        uint256 expectedId = _expectedId("test2");

        uint256 tokenId = registry.register("test2", owner, registry, address(0), lockedSubregistryRoleBitmap, uint64(block.timestamp) + 86400);
        vm.assertEq(tokenId, expectedId);
        
        // Verify roles
        assertFalse(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, owner));
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, owner));
    }

    function test_register_locked_resolver() public {
        uint256 expectedId = _expectedId("test2");

        uint256 tokenId = registry.register("test2", owner, registry, address(0), lockedResolverRoleBitmap, uint64(block.timestamp) + 86400);
        vm.assertEq(tokenId, expectedId);
        
        // Verify roles
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, owner));
        assertFalse(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, owner));
    }

    function test_Revert_cannot_mint_duplicates() public {
        registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 86400);

        vm.expectRevert(abi.encodeWithSelector(IPermissionedRegistry.NameAlreadyRegistered.selector, "test2"));
        registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 86400);
    }

    function test_set_subregistry() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 86400);
        registry.setSubregistry(tokenId, IRegistry(address(this)));
        vm.assertEq(address(registry.getSubregistry("test2")), address(this));
    }

    function test_Revert_cannot_set_subregistry_without_role() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), lockedSubregistryRoleBitmap, uint64(block.timestamp) + 86400);

        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, user1));
        vm.prank(user1);
        registry.setSubregistry(tokenId, IRegistry(user1));
    }

    function test_set_resolver() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 86400);
        registry.setResolver(tokenId, address(this));
        vm.assertEq(address(registry.getResolver("test2")), address(this));
    }

    function test_Revert_cannot_set_resolver_without_role() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), lockedResolverRoleBitmap, uint64(block.timestamp) + 86400);

        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, user1));
        vm.prank(user1);
        registry.setResolver(tokenId, address(this));
    }

    function test_renew_extends_expiry() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 100);
        uint64 newExpiry = uint64(block.timestamp) + 200;
        registry.renew(tokenId, newExpiry);
        
        uint64 expiry = registry.getExpiry(tokenId);
        assertEq(expiry, newExpiry);
    }

    function test_renew_emits_event() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 100);
        uint64 newExpiry = uint64(block.timestamp) + 200;
        
        vm.recordLogs();
        registry.renew(tokenId, newExpiry);
        
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 2);
        assertEq(entries[1].topics[0], keccak256("NameRenewed(uint256,uint64,address)"));
        assertEq(entries[1].topics[1], bytes32(tokenId));   
        (uint64 expiry, address renewedBy) = abi.decode(entries[1].data, (uint64, address));
        assertEq(expiry, newExpiry);
        assertEq(renewedBy, address(this));
    }

    function test_Revert_renew_expired_name() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 100);
        vm.warp(block.timestamp + 101);
        
        vm.expectRevert(abi.encodeWithSelector(IPermissionedRegistry.NameExpired.selector, tokenId));
        registry.renew(tokenId, uint64(block.timestamp) + 200);
    }

    function test_Revert_renew_reduce_expiry() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 200);
        uint64 newExpiry = uint64(block.timestamp) + 100;
        
        vm.expectRevert(abi.encodeWithSelector(IPermissionedRegistry.CannotReduceExpiration.selector, uint64(block.timestamp) + 200, newExpiry));
        registry.renew(tokenId, newExpiry);
    }

    function test_relinquish() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 86400);
        registry.relinquish(tokenId);
        vm.assertEq(registry.ownerOf(tokenId), address(0));
        vm.assertEq(address(registry.getSubregistry("test2")), address(0));
    }

    function test_relinquish_revokes_roles() public {
        uint256 tokenId = registry.register("test2", owner, registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 86400);
        
        // Verify roles before relinquishing
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, owner));
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, owner));
        
        vm.prank(owner);
        registry.relinquish(tokenId);
        
        // Verify roles are revoked after relinquishing
        assertFalse(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, owner));
        assertFalse(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, owner));
    }

    function test_relinquish_emits_event() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 100);
        
        vm.recordLogs();
        registry.relinquish(tokenId);
        
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 5);
        assertEq(entries[4].topics[0], keccak256("NameRelinquished(uint256,address)"));
        assertEq(entries[4].topics[1], bytes32(tokenId));
        (address relinquishedBy) = abi.decode(entries[4].data, (address));
        assertEq(relinquishedBy, address(this));
    }

    function test_Revert_cannot_relinquish_if_not_owner() public {
        uint256 tokenId = registry.register("test2", address(1), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 86400);

        vm.prank(address(2));
        vm.expectRevert(abi.encodeWithSelector(BaseRegistry.AccessDenied.selector, tokenId, address(1), address(2)));
        registry.relinquish(tokenId);

        vm.assertEq(registry.ownerOf(tokenId), address(1));
        vm.assertEq(address(registry.getSubregistry("test2")), address(registry));
    }

    function test_expired_name_has_no_owner() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 100);
        vm.warp(block.timestamp + 101);
        assertEq(registry.ownerOf(tokenId), address(0));
    }

    function test_expired_name_can_be_reregistered() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 100);
        vm.warp(block.timestamp + 101);
        
        uint256 newTokenId = registry.register("test2", address(1), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 100);
        assertEq(newTokenId, tokenId);
        assertEq(registry.ownerOf(newTokenId), address(1));
    }

    function test_expired_name_returns_zero_subregistry() public {
        registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 100);
        vm.warp(block.timestamp + 101);
        assertEq(address(registry.getSubregistry("test2")), address(0));
    }

    function test_expired_name_returns_zero_resolver() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 100);
        registry.setResolver(tokenId, address(1));
        vm.warp(block.timestamp + 101);
        assertEq(registry.getResolver("test2"), address(0));
    }

    // Token observers

    function test_token_observer_renew() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 100);
        registry.setTokenObserver(tokenId, address(observer));
        
        uint64 newExpiry = uint64(block.timestamp) + 200;
        registry.renew(tokenId, newExpiry);
        
        assertEq(observer.lastTokenId(), tokenId);
        assertEq(observer.lastExpiry(), newExpiry);
        assertEq(observer.lastCaller(), address(this));
        assertEq(observer.wasRelinquished(), false);
    }

    function test_token_observer_relinquish() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 100);
        registry.setTokenObserver(tokenId, address(observer));
        
        registry.relinquish(tokenId);
        
        assertEq(observer.lastTokenId(), tokenId);
        assertEq(observer.lastCaller(), address(this));
        assertEq(observer.wasRelinquished(), true);
    }

    function test_Revert_set_token_observer_if_not_owner_with_role() public {
        // Register a token with a specific owner
        address tokenOwner = address(1);
        uint256 tokenId = registry.register("test2", tokenOwner, registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 100);
        
        // Create a user who is not the owner and has no roles
        address randomUser = address(2);
        assertFalse(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_TOKEN_OBSERVER, randomUser));
        assertNotEq(registry.ownerOf(tokenId), randomUser);
        
        // When this user tries to set the token observer, it should revert
        vm.startPrank(randomUser);
        vm.expectRevert(abi.encodeWithSelector(
            EnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
            registry.tokenIdResource(tokenId),
            ROLE_SET_TOKEN_OBSERVER,
            randomUser
        ));
        registry.setTokenObserver(tokenId, address(observer));
        vm.stopPrank();
    }

    function test_token_owner_without_role_cannot_set_observer() public {
        // Register a token with NO token observer role
        uint256 roleBitmap = ROLE_SET_SUBREGISTRY | ROLE_SET_RESOLVER; // Explicitly exclude ROLE_SET_TOKEN_OBSERVER
        uint256 tokenId = registry.register("test2", user1, registry, address(0), roleBitmap, uint64(block.timestamp) + 86400);
        
        // Verify the owner doesn't have the SET_TOKEN_OBSERVER role
        assertFalse(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_TOKEN_OBSERVER, user1));
        
        // Owner should not be able to set token observer without the role
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, registry.tokenIdResource(tokenId), ROLE_SET_TOKEN_OBSERVER, user1));
        vm.prank(user1);
        registry.setTokenObserver(tokenId, address(observer));
    }

    function test_non_owner_with_role_can_set_observer() public {
        uint256 tokenId = registry.register("test2", user1, registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 86400);
        
        address tokenObserverSetter = makeAddr("tokenObserverSetter");
        
        // Grant the SET_TOKEN_OBSERVER role specifically for this token to a non-owner
        registry.grantRoles(registry.tokenIdResource(tokenId), ROLE_SET_TOKEN_OBSERVER, tokenObserverSetter);
        
        // Verify the role was granted
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_TOKEN_OBSERVER, tokenObserverSetter));
        
        // The non-owner with role should be able to set the token observer
        vm.prank(tokenObserverSetter);
        registry.setTokenObserver(tokenId, address(observer));
        
        // Verify observer was set
        vm.prank(user1);
        registry.relinquish(tokenId);
        assertEq(observer.lastTokenId(), tokenId);
        assertEq(observer.wasRelinquished(), true);
    }

    function test_Revert_renew_when_token_observer_reverts() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 100);
        registry.setTokenObserver(tokenId, address(revertingObserver));
        
        uint64 newExpiry = uint64(block.timestamp) + 200;
        vm.expectRevert(RevertingTokenObserver.ObserverReverted.selector);
        registry.renew(tokenId, newExpiry);
        
        uint64 expiry = registry.getExpiry(tokenId);
        assertEq(expiry, uint64(block.timestamp) + 100);
    }

    function test_Revert_relinquish_when_token_observer_reverts() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 100);
        registry.setTokenObserver(tokenId, address(revertingObserver));
        
        vm.expectRevert(RevertingTokenObserver.ObserverReverted.selector);
        registry.relinquish(tokenId);
        
        assertEq(registry.ownerOf(tokenId), address(this));
    }

    function test_set_token_observer_emits_event() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 100);
        
        vm.recordLogs();
        registry.setTokenObserver(tokenId, address(observer));
        
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("TokenObserverSet(uint256,address)"));
        assertEq(entries[0].topics[1], bytes32(tokenId));
        address observerAddress = abi.decode(entries[0].data, (address));
        assertEq(observerAddress, address(observer));
    }

    function test_expired_name_reregistration_resets_roles() public {
        // Register a name with owner1
        address owner1 = makeAddr("owner1");
        uint256 tokenId = registry.register("resettest", owner1, registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 100);
        
        // Grant an additional role to owner1
        registry.grantRoles(registry.tokenIdResource(tokenId), ROLE_RENEW, owner1);
        
        // Verify owner1 has roles
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, owner1));
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, owner1));
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_TOKEN_OBSERVER, owner1));
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_RENEW, owner1));
        
        // Capture the resource ID before expiration
        bytes32 originalResourceId = registry.tokenIdResource(tokenId);
        
        // Move time forward to expire the name
        vm.warp(block.timestamp + 101);
        
        // Verify token is expired
        assertEq(registry.ownerOf(tokenId), address(0));
        
        // Re-register with owner2
        address owner2 = makeAddr("owner2");
        uint256 newTokenId = registry.register("resettest", owner2, registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 100);
        
        // Verify it's the same token ID but has a different resource ID
        assertEq(newTokenId, tokenId);
        bytes32 newResourceId = registry.tokenIdResource(tokenId);
        assertNotEq(newResourceId, originalResourceId, "Resource ID should change after re-registration");
        
        // Since resource ID changed, owner1 should no longer have roles for this token
        // Test specifically using new resource ID
        assertFalse(registry.hasRoles(newResourceId, ROLE_SET_SUBREGISTRY, owner1));
        assertFalse(registry.hasRoles(newResourceId, ROLE_SET_RESOLVER, owner1));
        assertFalse(registry.hasRoles(newResourceId, ROLE_SET_TOKEN_OBSERVER, owner1));
        assertFalse(registry.hasRoles(newResourceId, ROLE_RENEW, owner1));
        
        // And owner2 should have the default roles
        assertTrue(registry.hasRoles(newResourceId, ROLE_SET_SUBREGISTRY, owner2));
        assertTrue(registry.hasRoles(newResourceId, ROLE_SET_RESOLVER, owner2));
        assertTrue(registry.hasRoles(newResourceId, ROLE_SET_TOKEN_OBSERVER, owner2));
    }
    
    function test_token_transfer_resets_roles() public {
        // Register a name with owner1
        address owner1 = makeAddr("owner1");
        uint256 tokenId = registry.register("transfertest", owner1, registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 100);
        
        // Grant additional role to owner1
        registry.grantRoles(registry.tokenIdResource(tokenId), ROLE_RENEW, owner1);
        
        // Verify owner1 has roles
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, owner1));
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, owner1));
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_TOKEN_OBSERVER, owner1));
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_RENEW, owner1));
        
        // Capture the resource ID before transfer
        bytes32 originalResourceId = registry.tokenIdResource(tokenId);
        
        // Transfer to owner2
        address owner2 = makeAddr("owner2");
        vm.prank(owner1);
        registry.safeTransferFrom(owner1, owner2, tokenId, 1, "");
        
        // Verify token ownership transferred
        assertEq(registry.ownerOf(tokenId), owner2);
        
        // Verify the resource ID has changed
        bytes32 newResourceId = registry.tokenIdResource(tokenId);
        assertNotEq(newResourceId, originalResourceId, "Resource ID should change after transfer");
        
        // Check using the new resource ID that owner1 no longer has roles
        assertFalse(registry.hasRoles(newResourceId, ROLE_SET_SUBREGISTRY, owner1));
        assertFalse(registry.hasRoles(newResourceId, ROLE_SET_RESOLVER, owner1));
        assertFalse(registry.hasRoles(newResourceId, ROLE_SET_TOKEN_OBSERVER, owner1));
        assertFalse(registry.hasRoles(newResourceId, ROLE_RENEW, owner1));
        
        // New owner should not automatically receive any roles after transfer
        assertFalse(registry.hasRoles(newResourceId, ROLE_SET_SUBREGISTRY, owner2));
        assertFalse(registry.hasRoles(newResourceId, ROLE_SET_RESOLVER, owner2));
        assertFalse(registry.hasRoles(newResourceId, ROLE_SET_TOKEN_OBSERVER, owner2));
    }

    function test_Revert_setTokenObserver_when_token_expired() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 100);
        
        vm.warp(block.timestamp + 101);
        
        vm.expectRevert(abi.encodeWithSelector(IPermissionedRegistry.NameExpired.selector, tokenId));
        registry.setTokenObserver(tokenId, address(observer));
    }

    function test_Revert_setSubregistry_when_token_expired() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 100);
        
        vm.warp(block.timestamp + 101);
        
        vm.expectRevert(abi.encodeWithSelector(IPermissionedRegistry.NameExpired.selector, tokenId));
        registry.setSubregistry(tokenId, IRegistry(address(this)));
    }

    function test_Revert_setResolver_when_token_expired() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), defaultRoleBitmap, uint64(block.timestamp) + 100);
        
        vm.warp(block.timestamp + 101);
        
        vm.expectRevert(abi.encodeWithSelector(IPermissionedRegistry.NameExpired.selector, tokenId));
        registry.setResolver(tokenId, address(this));
    }

    function test_Revert_setTokenObserver_without_role_when_expired() public {
        uint256 tokenId = registry.register("test2", user1, registry, address(0), noRolesRoleBitmap, uint64(block.timestamp) + 100);
        
        vm.warp(block.timestamp + 101);
        
        vm.expectRevert(abi.encodeWithSelector(
            EnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
            registry.tokenIdResource(tokenId),
            ROLE_SET_TOKEN_OBSERVER,
            user1
        ));
        vm.prank(user1);
        registry.setTokenObserver(tokenId, address(observer));
    }

    function test_Revert_setSubregistry_without_role_when_expired() public {
        uint256 tokenId = registry.register("test2", user1, registry, address(0), noRolesRoleBitmap, uint64(block.timestamp) + 100);
        
        vm.warp(block.timestamp + 101);
        
        vm.expectRevert(abi.encodeWithSelector(
            EnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
            registry.tokenIdResource(tokenId),
            ROLE_SET_SUBREGISTRY,
            user1
        ));
        vm.prank(user1);
        registry.setSubregistry(tokenId, IRegistry(address(this)));
    }

    function test_Revert_setResolver_without_role_when_expired() public {
        uint256 tokenId = registry.register("test2", user1, registry, address(0), noRolesRoleBitmap, uint64(block.timestamp) + 100);
        
        vm.warp(block.timestamp + 101);
        
        vm.expectRevert(abi.encodeWithSelector(
            EnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
            registry.tokenIdResource(tokenId),
            ROLE_SET_RESOLVER,
            user1
        ));
        vm.prank(user1);
        registry.setResolver(tokenId, address(this));
    }

    function test_setTokenObserver_with_role_when_not_expired() public {
        uint256 tokenId = registry.register("test2", user1, registry, address(0), ROLE_SET_TOKEN_OBSERVER, uint64(block.timestamp) + 100);
        
        vm.prank(user1);
        registry.setTokenObserver(tokenId, address(observer));
        
        assertEq(address(registry.tokenObservers(tokenId)), address(observer));
    }

    function test_setSubregistry_with_role_when_not_expired() public {
        uint256 tokenId = registry.register("test2", user1, registry, address(0), ROLE_SET_SUBREGISTRY, uint64(block.timestamp) + 100);
        
        vm.prank(user1);
        registry.setSubregistry(tokenId, IRegistry(address(this)));
        
        assertEq(address(registry.getSubregistry("test2")), address(this));
    }

    function test_setResolver_with_role_when_not_expired() public {
        uint256 tokenId = registry.register("test2", user1, registry, address(0), ROLE_SET_RESOLVER, uint64(block.timestamp) + 100);
        
        vm.prank(user1);
        registry.setResolver(tokenId, address(this));
        
        assertEq(registry.getResolver("test2"), address(this));
    }

    function test_Revert_setTokenObserver_without_role_when_not_expired() public {
        uint256 tokenId = registry.register("test2", user1, registry, address(0), noRolesRoleBitmap, uint64(block.timestamp) + 100);
        
        vm.expectRevert(abi.encodeWithSelector(
            EnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
            registry.tokenIdResource(tokenId),
            ROLE_SET_TOKEN_OBSERVER,
            user1
        ));
        vm.prank(user1);
        registry.setTokenObserver(tokenId, address(observer));
    }

    function test_Revert_setSubregistry_without_role_when_not_expired() public {
        uint256 tokenId = registry.register("test2", user1, registry, address(0), noRolesRoleBitmap, uint64(block.timestamp) + 100);
        
        vm.expectRevert(abi.encodeWithSelector(
            EnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
            registry.tokenIdResource(tokenId),
            ROLE_SET_SUBREGISTRY,
            user1
        ));
        vm.prank(user1);
        registry.setSubregistry(tokenId, IRegistry(address(this)));
    }

    function test_Revert_setResolver_without_role_when_not_expired() public {
        uint256 tokenId = registry.register("test2", user1, registry, address(0), noRolesRoleBitmap, uint64(block.timestamp) + 100);
        
        vm.expectRevert(abi.encodeWithSelector(
            EnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
            registry.tokenIdResource(tokenId),
            ROLE_SET_RESOLVER,
            user1
        ));
        vm.prank(user1);
        registry.setResolver(tokenId, address(this));
    }
}


contract MockTokenObserver is TokenObserver {
    uint256 public lastTokenId;
    uint64 public lastExpiry;
    address public lastCaller;
    bool public wasRelinquished;

    function onRenew(uint256 tokenId, uint64 expires, address renewedBy) external {
        lastTokenId = tokenId;
        lastExpiry = expires;
        lastCaller = renewedBy;
        wasRelinquished = false;
    }

    function onRelinquish(uint256 tokenId, address relinquishedBy) external {
        lastTokenId = tokenId;
        lastCaller = relinquishedBy;
        wasRelinquished = true;
    }
}

contract RevertingTokenObserver is TokenObserver {
    error ObserverReverted();

    function onRenew(uint256, uint64, address) external pure {
        revert ObserverReverted();
    }

    function onRelinquish(uint256, address) external pure {
        revert ObserverReverted();
    }
}

contract MockPriceOracle is IPriceOracle {
    function price(string memory, uint256, uint256) external pure override returns (Price memory) {
        return Price({
            base: 0.01 ether,
            premium: 0
        });
    }
}