// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "../src/registry/ETHRegistry.sol";
import "../src/registry/IETHRegistry.sol";
import "../src/registry/RegistryDatastore.sol";
import "../src/registry/RegistryDatastore.sol";
import "../src/registry/RegistryMetadata.sol";
import "../src/registry/SimpleRegistryMetadata.sol";
import "../src/registry/ETHRegistrar.sol";
import "../src/registry/IPriceOracle.sol";


contract TestETHRegistry is Test, ERC1155Holder {
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);

    RegistryDatastore datastore;
    ETHRegistry registry;
    ETHRegistrar registrar;
    MockTokenObserver observer;
    RevertingTokenObserver revertingObserver;
    RegistryMetadata metadata;
    MockPriceOracle priceOracle;

    // Role bitmaps for different permission configurations
    uint256 constant ROLE_SET_SUBREGISTRY = 1 << 0;
    uint256 constant ROLE_SET_RESOLVER = 1 << 1;
    uint256 constant defaultRoleBitmap = ROLE_SET_SUBREGISTRY | ROLE_SET_RESOLVER;
    uint256 constant lockedResolverRoleBitmap = ROLE_SET_SUBREGISTRY;
    uint256 constant lockedSubregistryRoleBitmap = ROLE_SET_RESOLVER;
    uint256 constant noRolesRoleBitmap = 0;

    address owner = makeAddr("owner");
    address user1 = makeAddr("user1");

    function setUp() public {
        datastore = new RegistryDatastore();
        metadata = new SimpleRegistryMetadata();
        registry = new ETHRegistry(datastore, metadata);
        registry.grantRootRoles(registry.ROLE_REGISTRAR(), address(this));
        observer = new MockTokenObserver();
        revertingObserver = new RevertingTokenObserver();
        priceOracle = new MockPriceOracle();
        registrar = new ETHRegistrar(address(registry), priceOracle, 60, 86400);
    }

    function test_constructor_sets_roles() public view {
        uint256 r = registry.ROLE_REGISTRAR() | registry.ROLE_REGISTRAR_ADMIN() | registry.ROLE_RENEW() | registry.ROLE_RENEW_ADMIN();
        assertTrue(registry.hasRoles(registry.ROOT_RESOURCE(), r, address(this)));
    }

    function test_Revert_register_without_registrar_role() public {
        address nonRegistrar = makeAddr("nonRegistrar");

        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, registry.ROOT_RESOURCE(), registry.ROLE_REGISTRAR(), nonRegistrar));
        vm.prank(nonRegistrar);
        registry.register("test2", address(this), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 86400);
    }

    function test_Revert_renew_without_renew_role() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 86400);
        
        address nonRenewer = makeAddr("nonRenewer");

        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, registry.ROOT_RESOURCE(), registry.ROLE_RENEW(), nonRenewer));
        vm.prank(nonRenewer);
        registry.renew(tokenId, uint64(block.timestamp) + 172800);
    }

    function test_registrar_can_register() public {
        address registrar2 = makeAddr("registrar");
        registry.grantRootRoles(registry.ROLE_REGISTRAR(), registrar2);
        
        vm.prank(registrar2);
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 86400);
        assertEq(registry.ownerOf(tokenId), address(this));
    }

    function test_renewer_can_renew() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 86400);
        
        address renewer = makeAddr("renewer");
        registry.grantRootRoles(registry.ROLE_RENEW(), renewer);
        
        vm.prank(renewer);
        uint64 newExpiry = uint64(block.timestamp) + 172800;
        registry.renew(tokenId, newExpiry);
        
        (uint64 expiry,) = registry.nameData(tokenId);
        assertEq(expiry, newExpiry);
    }

    function _expectedId(string memory label, uint96 flags) internal view returns (uint256) {
        return (uint256(keccak256(bytes(label))) & ~uint256(registry.FLAGS_MASK())) | flags;
    }

    function test_register_unlocked() public {
        uint256 expectedId = _expectedId("test2", 0);

        uint256 tokenId = registry.register("test2", owner, registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 86400);
        vm.assertEq(tokenId, expectedId);
        
        // Verify roles
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, owner));
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, owner));
    }

    function test_register_locked() public {
        uint96 flags = 0; // No flags set, just using roleBitmap for locking
        uint256 expectedId = _expectedId("test2", flags);

        uint256 tokenId = registry.register("test2", owner, registry, address(0), flags, noRolesRoleBitmap, uint64(block.timestamp) + 86400);
        vm.assertEq(tokenId, expectedId);
        
        // Verify roles
        assertFalse(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, owner));
        assertFalse(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, owner));
    }

    function test_register_locked_subregistry() public {
        uint96 flags = 0; // No flags set, just using roleBitmap for locking
        uint256 expectedId = _expectedId("test2", flags);

        uint256 tokenId = registry.register("test2", owner, registry, address(0), flags, lockedSubregistryRoleBitmap, uint64(block.timestamp) + 86400);
        vm.assertEq(tokenId, expectedId);
        
        // Verify roles
        assertFalse(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, owner));
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, owner));
    }

    function test_register_locked_resolver() public {
        uint96 flags = 0; // No flags set, just using roleBitmap for locking
        uint256 expectedId = _expectedId("test2", flags);

        uint256 tokenId = registry.register("test2", owner, registry, address(0), flags, lockedResolverRoleBitmap, uint64(block.timestamp) + 86400);
        vm.assertEq(tokenId, expectedId);
        
        // Verify roles
        assertTrue(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, owner));
        assertFalse(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, owner));
    }

    function test_lock_name() public {
        uint256 oldTokenId = registry.register("test2", owner, registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 86400);

        uint96 flags = registry.FLAG_FLAGS_LOCKED();
        uint256 expectedTokenId = (oldTokenId & ~uint256(registry.FLAGS_MASK())) | (flags & registry.FLAGS_MASK());
        vm.prank(owner);
        uint256 newTokenId = registry.setFlags(oldTokenId, flags);
        vm.assertNotEq(newTokenId, oldTokenId);
        vm.assertEq(newTokenId, expectedTokenId);
        
        // Verify roles are preserved after flag change
        assertTrue(registry.hasRoles(registry.tokenIdResource(newTokenId), ROLE_SET_SUBREGISTRY, owner));
        assertTrue(registry.hasRoles(registry.tokenIdResource(newTokenId), ROLE_SET_RESOLVER, owner));
    }

    function test_cannot_unlock_name() public {
        uint96 flags = registry.FLAG_FLAGS_LOCKED();
        uint256 oldTokenId = registry.register("test2", owner, registry, address(0), flags, defaultRoleBitmap, uint64(block.timestamp) + 86400);

        vm.expectRevert(abi.encodeWithSelector(BaseRegistry.InvalidSubregistryFlags.selector, oldTokenId, flags, 0));
        vm.prank(owner);
        registry.setFlags(oldTokenId, 0);
    }

    function test_Revert_cannot_mint_duplicates() public {
        registry.register("test2", address(this), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 86400);

        vm.expectRevert(abi.encodeWithSelector(IETHRegistry.NameAlreadyRegistered.selector, "test2"));
        registry.register("test2", address(this), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 86400);
    }

    function test_set_subregistry() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 86400);
        registry.setSubregistry(tokenId, IRegistry(address(this)));
        vm.assertEq(address(registry.getSubregistry("test2")), address(this));
    }

    function test_Revert_cannot_set_subregistry_without_role() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), 0, lockedSubregistryRoleBitmap, uint64(block.timestamp) + 86400);

        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, user1));
        vm.prank(user1);
        registry.setSubregistry(tokenId, IRegistry(user1));
    }

    function test_set_resolver() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 86400);
        registry.setResolver(tokenId, address(this));
        vm.assertEq(address(registry.getResolver("test2")), address(this));
    }

    function test_Revert_cannot_set_resolver_without_role() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), 0, lockedResolverRoleBitmap, uint64(block.timestamp) + 86400);

        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, user1));
        vm.prank(user1);
        registry.setResolver(tokenId, address(this));
    }

    function test_Revert_cannot_set_locked_flags() public {
        uint96 flags = registry.FLAG_FLAGS_LOCKED();
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), flags, 0, uint64(block.timestamp) + 86400);

        vm.expectRevert(abi.encodeWithSelector(BaseRegistry.InvalidSubregistryFlags.selector, tokenId, registry.FLAG_FLAGS_LOCKED(), 0));
        registry.setFlags(tokenId, flags);
    }

    function test_renew_extends_expiry() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 100);
        uint64 newExpiry = uint64(block.timestamp) + 200;
        registry.renew(tokenId, newExpiry);
        
        (uint64 expiry,) = registry.nameData(tokenId);
        assertEq(expiry, newExpiry);
    }

    function test_renew_emits_event() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 100);
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
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 100);
        vm.warp(block.timestamp + 101);
        
        vm.expectRevert(abi.encodeWithSelector(IETHRegistry.NameExpired.selector, tokenId));
        registry.renew(tokenId, uint64(block.timestamp) + 200);
    }

    function test_Revert_renew_reduce_expiry() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 200);
        uint64 newExpiry = uint64(block.timestamp) + 100;
        
        vm.expectRevert(abi.encodeWithSelector(IETHRegistry.CannotReduceExpiration.selector, uint64(block.timestamp) + 200, newExpiry));
        registry.renew(tokenId, newExpiry);
    }

    function test_relinquish() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 86400);
        registry.relinquish(tokenId);
        vm.assertEq(registry.ownerOf(tokenId), address(0));
        vm.assertEq(address(registry.getSubregistry("test2")), address(0));
    }

    function test_relinquish_revokes_roles() public {
        uint256 tokenId = registry.register("test2", owner, registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 86400);
        
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
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 100);
        
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
        uint256 tokenId = registry.register("test2", address(1), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 86400);

        vm.prank(address(2));
        vm.expectRevert(abi.encodeWithSelector(BaseRegistry.AccessDenied.selector, tokenId, address(1), address(2)));
        registry.relinquish(tokenId);

        vm.assertEq(registry.ownerOf(tokenId), address(1));
        vm.assertEq(address(registry.getSubregistry("test2")), address(registry));
    }

    function test_expired_name_has_no_owner() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 100);
        vm.warp(block.timestamp + 101);
        assertEq(registry.ownerOf(tokenId), address(0));
    }

    function test_expired_name_can_be_reregistered() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 100);
        vm.warp(block.timestamp + 101);
        
        uint256 newTokenId = registry.register("test2", address(1), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 100);
        assertEq(newTokenId, tokenId);
        assertEq(registry.ownerOf(newTokenId), address(1));
    }

    function test_expired_name_returns_zero_subregistry() public {
        registry.register("test2", address(this), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 100);
        vm.warp(block.timestamp + 101);
        assertEq(address(registry.getSubregistry("test2")), address(0));
    }

    function test_expired_name_returns_zero_resolver() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 100);
        registry.setResolver(tokenId, address(1));
        vm.warp(block.timestamp + 101);
        assertEq(registry.getResolver("test2"), address(0));
    }

    function test_setFlags_moves_roles_to_new_token_id_resource() public {
        // Register with default roles
        uint256 tokenId = registry.register("test2", user1, registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 86400);

        // Verify initial roles
        assertEq(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_SUBREGISTRY, user1), true);
        assertEq(registry.hasRoles(registry.tokenIdResource(tokenId), ROLE_SET_RESOLVER, user1), true);
        
        // Set a flag that changes the token ID
        uint96 flags = 0x4; // Some arbitrary flag that's not FLAG_FLAGS_LOCKED
        vm.prank(user1);
        uint256 newTokenId = registry.setFlags(tokenId, flags);
        assertNotEq(newTokenId, tokenId);
        
        // Verify roles are copied after flag change
        assertEq(registry.hasRoles(registry.tokenIdResource(newTokenId), ROLE_SET_SUBREGISTRY, user1), true);
        assertEq(registry.hasRoles(registry.tokenIdResource(newTokenId), ROLE_SET_RESOLVER, user1), true);
    }

    // Token observers

    function test_token_observer_renew() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 100);
        registry.setTokenObserver(tokenId, address(observer));
        
        uint64 newExpiry = uint64(block.timestamp) + 200;
        registry.renew(tokenId, newExpiry);
        
        assertEq(observer.lastTokenId(), tokenId);
        assertEq(observer.lastExpiry(), newExpiry);
        assertEq(observer.lastCaller(), address(this));
        assertEq(observer.wasRelinquished(), false);
    }

    function test_token_observer_relinquish() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 100);
        registry.setTokenObserver(tokenId, address(observer));
        
        registry.relinquish(tokenId);
        
        assertEq(observer.lastTokenId(), tokenId);
        assertEq(observer.lastCaller(), address(this));
        assertEq(observer.wasRelinquished(), true);
    }

    function test_Revert_set_token_observer_if_not_owner() public {
        uint256 tokenId = registry.register("test2", address(1), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 100);
        
        vm.prank(address(2));
        vm.expectRevert(abi.encodeWithSelector(BaseRegistry.AccessDenied.selector, tokenId, address(1), address(2)));
        registry.setTokenObserver(tokenId, address(observer));
    }

    function test_Revert_renew_when_token_observer_reverts() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 100);
        registry.setTokenObserver(tokenId, address(revertingObserver));
        
        uint64 newExpiry = uint64(block.timestamp) + 200;
        vm.expectRevert(RevertingTokenObserver.ObserverReverted.selector);
        registry.renew(tokenId, newExpiry);
        
        (uint64 expiry,) = registry.nameData(tokenId);
        assertEq(expiry, uint64(block.timestamp) + 100);
    }

    function test_Revert_relinquish_when_token_observer_reverts() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 100);
        registry.setTokenObserver(tokenId, address(revertingObserver));
        
        vm.expectRevert(RevertingTokenObserver.ObserverReverted.selector);
        registry.relinquish(tokenId);
        
        assertEq(registry.ownerOf(tokenId), address(this));
    }

    function test_set_token_observer_emits_event() public {
        uint256 tokenId = registry.register("test2", address(this), registry, address(0), 0, defaultRoleBitmap, uint64(block.timestamp) + 100);
        
        vm.recordLogs();
        registry.setTokenObserver(tokenId, address(observer));
        
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("TokenObserverSet(uint256,address)"));
        assertEq(entries[0].topics[1], bytes32(tokenId));
        address observerAddress = abi.decode(entries[0].data, (address));
        assertEq(observerAddress, address(observer));
    }
}


contract MockTokenObserver is ETHRegistryTokenObserver {
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

contract RevertingTokenObserver is ETHRegistryTokenObserver {
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
