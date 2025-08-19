// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "./mocks/MockPermissionedRegistry.sol";
import "../src/common/RegistryDatastore.sol";
import "../src/common/IRegistryMetadata.sol";
import "../src/common/SimpleRegistryMetadata.sol";
import "../src/common/BaseRegistry.sol";
import "../src/common/IPermissionedRegistry.sol";
import "../src/common/ITokenObserver.sol";
import {LibEACBaseRoles} from "../src/common/EnhancedAccessControl.sol";
import {IEnhancedAccessControl} from "../src/common/IEnhancedAccessControl.sol";
import {LibRegistryRoles} from "../src/common/LibRegistryRoles.sol";

contract TestPermissionedRegistry is Test, ERC1155Holder {
    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );

    RegistryDatastore datastore;
    MockPermissionedRegistry registry;
    MockTokenObserver observer;
    RevertingTokenObserver revertingObserver;
    IRegistryMetadata metadata;

    // Role bitmaps for different permission configurations

    uint256 constant defaultRoleBitmap =
        LibRegistryRoles.ROLE_SET_SUBREGISTRY |
            LibRegistryRoles.ROLE_SET_RESOLVER |
            LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER;
    uint256 constant lockedResolverRoleBitmap =
        LibRegistryRoles.ROLE_SET_SUBREGISTRY |
            LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER;
    uint256 constant lockedSubregistryRoleBitmap =
        LibRegistryRoles.ROLE_SET_RESOLVER |
            LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER;
    uint256 constant noRolesRoleBitmap = 0;

    address owner = makeAddr("owner");
    address user1 = makeAddr("user1");

    // all roles
    uint256 deployerRoles = LibEACBaseRoles.ALL_ROLES;

    function setUp() public {
        datastore = new RegistryDatastore();
        metadata = new SimpleRegistryMetadata();
        registry = new MockPermissionedRegistry(
            datastore,
            metadata,
            address(this),
            deployerRoles
        );
        observer = new MockTokenObserver();
        revertingObserver = new RevertingTokenObserver();
    }

    function test_constructor_sets_roles() public view {
        uint256 expectedRoles = deployerRoles;
        assertTrue(
            registry.hasRoles(
                registry.ROOT_RESOURCE(),
                expectedRoles,
                address(this)
            )
        );
    }

    function test_Revert_register_without_registrar_role() public {
        address nonRegistrar = makeAddr("nonRegistrar");

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.ROOT_RESOURCE(),
                LibRegistryRoles.ROLE_REGISTRAR,
                nonRegistrar
            )
        );
        vm.prank(nonRegistrar);
        registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 86400
        );
    }

    function test_Revert_renew_without_renew_role() public {
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 86400
        );

        address nonRenewer = makeAddr("nonRenewer");

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_RENEW,
                nonRenewer
            )
        );
        vm.prank(nonRenewer);
        registry.renew(tokenId, uint64(block.timestamp) + 172800);
    }

    function test_token_specific_renewer_can_renew() public {
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 86400
        );

        address tokenRenewer = makeAddr("tokenRenewer");

        // Grant the RENEW role specifically for this token
        registry.grantRoles(
            registry.testGetResourceFromTokenId(tokenId),
            LibRegistryRoles.ROLE_RENEW,
            tokenRenewer
        );

        // Verify the role was granted
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_RENEW,
                tokenRenewer
            )
        );

        // This user doesn't have the ROOT_RESOURCE LibRegistryRoles.ROLE_RENEW
        assertFalse(
            registry.hasRoles(
                registry.ROOT_RESOURCE(),
                LibRegistryRoles.ROLE_RENEW,
                tokenRenewer
            )
        );

        // But should still be able to renew this specific token
        vm.prank(tokenRenewer);
        uint64 newExpiry = uint64(block.timestamp) + 172800;
        registry.renew(tokenId, newExpiry);

        uint64 expiry = registry.getExpiry(tokenId);
        assertEq(expiry, newExpiry);
    }

    function test_token_owner_can_renew_if_granted_role() public {
        // Register a token with specific roles including LibRegistryRoles.ROLE_RENEW
        uint256 roleBitmap = defaultRoleBitmap | LibRegistryRoles.ROLE_RENEW;
        uint256 tokenId = registry.register(
            "test2",
            user1,
            registry,
            address(0),
            roleBitmap,
            uint64(block.timestamp) + 86400
        );

        // Verify the owner has the RENEW role for this token
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_RENEW,
                user1
            )
        );

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
        uint256 tokenId = registry.register(
            "test2",
            tokenOwner,
            registry,
            address(0),
            noRolesRoleBitmap,
            uint64(block.timestamp) + 86400
        );

        // Verify the owner doesn't have the RENEW role for this token (this is the intent of the test)
        assertFalse(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_RENEW,
                tokenOwner
            )
        );

        // Owner should not be able to renew without the role
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_RENEW,
                tokenOwner
            )
        );
        vm.prank(tokenOwner);
        registry.renew(tokenId, uint64(block.timestamp) + 172800);
    }

    function test_registrar_can_register() public {
        address registrar2 = makeAddr("registrar");
        registry.grantRootRoles(LibRegistryRoles.ROLE_REGISTRAR, registrar2);

        vm.prank(registrar2);
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 86400
        );
        assertEq(registry.ownerOf(tokenId), address(this));
    }

    function test_renewer_can_renew() public {
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 86400
        );

        address renewer = makeAddr("renewer");
        registry.grantRootRoles(LibRegistryRoles.ROLE_RENEW, renewer);

        vm.prank(renewer);
        uint64 newExpiry = uint64(block.timestamp) + 172800;
        registry.renew(tokenId, newExpiry);

        uint64 expiry = registry.getExpiry(tokenId);
        assertEq(expiry, newExpiry);
    }

    function test_register_unlocked() public {
        uint256 tokenId = registry.register(
            "test2",
            owner,
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 86400
        );

        // Verify roles
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_SUBREGISTRY,
                owner
            )
        );
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_RESOLVER,
                owner
            )
        );
    }

    function test_register_locked() public {
        uint256 tokenId = registry.register(
            "test2",
            owner,
            registry,
            address(0),
            noRolesRoleBitmap,
            uint64(block.timestamp) + 86400
        );

        // Verify roles
        assertFalse(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_SUBREGISTRY,
                owner
            )
        );
        assertFalse(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_RESOLVER,
                owner
            )
        );
    }

    function test_register_locked_subregistry() public {
        uint256 tokenId = registry.register(
            "test2",
            owner,
            registry,
            address(0),
            lockedSubregistryRoleBitmap,
            uint64(block.timestamp) + 86400
        );

        // Verify roles
        assertFalse(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_SUBREGISTRY,
                owner
            )
        );
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_RESOLVER,
                owner
            )
        );
    }

    function test_register_locked_resolver() public {
        uint256 tokenId = registry.register(
            "test2",
            owner,
            registry,
            address(0),
            lockedResolverRoleBitmap,
            uint64(block.timestamp) + 86400
        );

        // Verify roles
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_SUBREGISTRY,
                owner
            )
        );
        assertFalse(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_RESOLVER,
                owner
            )
        );
    }

    function test_Revert_cannot_mint_duplicates() public {
        registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 86400
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IStandardRegistry.NameAlreadyRegistered.selector,
                "test2"
            )
        );
        registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 86400
        );
    }

    function test_set_subregistry() public {
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 86400
        );
        registry.setSubregistry(tokenId, IRegistry(address(this)));
        vm.assertEq(address(registry.getSubregistry("test2")), address(this));
    }

    function test_Revert_cannot_set_subregistry_without_role() public {
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            lockedSubregistryRoleBitmap,
            uint64(block.timestamp) + 86400
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_SUBREGISTRY,
                user1
            )
        );
        vm.prank(user1);
        registry.setSubregistry(tokenId, IRegistry(user1));
    }

    function test_set_resolver() public {
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 86400
        );
        registry.setResolver(tokenId, address(this));
        vm.assertEq(address(registry.getResolver("test2")), address(this));
    }

    function test_Revert_cannot_set_resolver_without_role() public {
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            lockedResolverRoleBitmap,
            uint64(block.timestamp) + 86400
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_RESOLVER,
                user1
            )
        );
        vm.prank(user1);
        registry.setResolver(tokenId, address(this));
    }

    function test_renew_extends_expiry() public {
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 100
        );
        uint64 newExpiry = uint64(block.timestamp) + 200;
        registry.renew(tokenId, newExpiry);

        uint64 expiry = registry.getExpiry(tokenId);
        assertEq(expiry, newExpiry);
    }

    function test_renew_emits_event() public {
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 100
        );
        uint64 newExpiry = uint64(block.timestamp) + 200;

        vm.recordLogs();
        registry.renew(tokenId, newExpiry);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 2);
        assertEq(
            entries[1].topics[0],
            keccak256("NameRenewed(uint256,uint64,address)")
        );
        assertEq(entries[1].topics[1], bytes32(tokenId));
        (uint64 expiry, address renewedBy) = abi.decode(
            entries[1].data,
            (uint64, address)
        );
        assertEq(expiry, newExpiry);
        assertEq(renewedBy, address(this));
    }

    function test_Revert_renew_expired_name() public {
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 100
        );
        vm.warp(block.timestamp + 101);

        vm.expectRevert(
            abi.encodeWithSelector(
                IStandardRegistry.NameExpired.selector,
                tokenId
            )
        );
        registry.renew(tokenId, uint64(block.timestamp) + 200);
    }

    function test_Revert_renew_reduce_expiry() public {
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 200
        );
        uint64 newExpiry = uint64(block.timestamp) + 100;

        vm.expectRevert(
            abi.encodeWithSelector(
                IStandardRegistry.CannotReduceExpiration.selector,
                uint64(block.timestamp) + 200,
                newExpiry
            )
        );
        registry.renew(tokenId, newExpiry);
    }

    function test_burn() public {
        uint256 roleBitmap = defaultRoleBitmap | LibRegistryRoles.ROLE_BURN;
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            roleBitmap,
            uint64(block.timestamp) + 86400
        );
        registry.burn(tokenId);
        vm.assertEq(registry.ownerOf(tokenId), address(0), "owner");
        vm.assertEq(
            address(registry.getSubregistry("test2")),
            address(0),
            "registry"
        );
        vm.assertEq(registry.mostRecentOwnerOf(tokenId), address(0), "recent"); // does not survive burn
    }

    function test_burn_revokes_roles() public {
        uint256 roleBitmap = defaultRoleBitmap | LibRegistryRoles.ROLE_BURN;
        uint256 tokenId = registry.register(
            "test2",
            owner,
            registry,
            address(0),
            roleBitmap,
            uint64(block.timestamp) + 86400
        );

        // Verify roles before burning
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_SUBREGISTRY,
                owner
            )
        );
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_RESOLVER,
                owner
            )
        );

        vm.prank(owner);
        registry.burn(tokenId);

        // Verify roles are revoked after burning
        assertFalse(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_SUBREGISTRY,
                owner
            )
        );
        assertFalse(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_RESOLVER,
                owner
            )
        );
    }

    function test_burn_emits_event() public {
        uint256 roleBitmap = defaultRoleBitmap | LibRegistryRoles.ROLE_BURN;
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            roleBitmap,
            uint64(block.timestamp) + 100
        );

        vm.recordLogs();
        registry.burn(tokenId);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 6);
        assertEq(
            entries[5].topics[0],
            keccak256("NameBurned(uint256,address)")
        );
        assertEq(entries[5].topics[1], bytes32(tokenId));
        address burnedBy = abi.decode(entries[5].data, (address));
        assertEq(burnedBy, address(this));
    }

    function test_Revert_cannot_burn_without_role() public {
        uint256 tokenId = registry.register(
            "test2",
            address(1),
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 86400
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_BURN,
                address(2)
            )
        );
        vm.prank(address(2));
        registry.burn(tokenId);

        vm.assertEq(registry.ownerOf(tokenId), address(1));
        vm.assertEq(
            address(registry.getSubregistry("test2")),
            address(registry)
        );
    }

    function test_expired_name_has_no_owner() public {
        address user = makeAddr("user");
        uint256 tokenId = registry.register(
            "test2",
            user,
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 100
        );
        vm.warp(block.timestamp + 101);
        assertEq(registry.ownerOf(tokenId), address(0), "owner");
        assertEq(registry.mostRecentOwnerOf(tokenId), user, "recent");
    }

    function test_expired_name_can_be_reregistered() public {
        string memory label = "test2";
        address user = makeAddr("user");
        uint256 tokenId = registry.register(
            label,
            user,
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 100
        );
        assertEq(registry.ownerOf(tokenId), user, "owner0");
        vm.warp(block.timestamp + 101);
        assertEq(registry.ownerOf(tokenId), address(0), "owner1");
        assertEq(registry.mostRecentOwnerOf(tokenId), user, "recent");
        address newUser = makeAddr("newUser");
        uint256 newTokenId = registry.register(
            label,
            newUser,
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 100
        );
        assertEq(registry.ownerOf(newTokenId), newUser, "owner2");
        assertEq(tokenId + 1, newTokenId, "token++");
    }

    function test_expired_name_returns_zero_subregistry() public {
        registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 100
        );
        vm.warp(block.timestamp + 101);
        assertEq(address(registry.getSubregistry("test2")), address(0));
    }

    function test_expired_name_returns_zero_resolver() public {
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 100
        );
        registry.setResolver(tokenId, address(1));
        vm.warp(block.timestamp + 101);
        assertEq(registry.getResolver("test2"), address(0));
    }

    // Token observers

    function test_token_observer_renew() public {
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 100
        );
        registry.setTokenObserver(tokenId, observer);

        uint64 newExpiry = uint64(block.timestamp) + 200;
        registry.renew(tokenId, newExpiry);

        assertEq(observer.lastTokenId(), tokenId);
        assertEq(observer.lastExpiry(), newExpiry);
        assertEq(observer.lastCaller(), address(this));
    }

    function test_Revert_set_token_observer_if_not_owner_with_role() public {
        // Register a token with a specific owner
        address tokenOwner = address(1);
        uint256 tokenId = registry.register(
            "test2",
            tokenOwner,
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 100
        );

        // Create a user who is not the owner and has no roles
        address randomUser = address(2);
        assertFalse(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER,
                randomUser
            )
        );
        assertNotEq(registry.ownerOf(tokenId), randomUser);

        // When this user tries to set the token observer, it should revert
        vm.startPrank(randomUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER,
                randomUser
            )
        );
        registry.setTokenObserver(tokenId, observer);
        vm.stopPrank();
    }

    function test_token_owner_without_role_cannot_set_observer() public {
        // Register a token with NO token observer role
        uint256 roleBitmap = LibRegistryRoles.ROLE_SET_SUBREGISTRY |
            LibRegistryRoles.ROLE_SET_RESOLVER; // Explicitly exclude LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER
        uint256 tokenId = registry.register(
            "test2",
            user1,
            registry,
            address(0),
            roleBitmap,
            uint64(block.timestamp) + 86400
        );

        // Verify the owner doesn't have the SET_TOKEN_OBSERVER role
        assertFalse(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER,
                user1
            )
        );

        // Owner should not be able to set token observer without the role
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER,
                user1
            )
        );
        vm.prank(user1);
        registry.setTokenObserver(tokenId, observer);
    }

    function test_non_owner_with_role_can_set_observer() public {
        uint256 tokenId = registry.register(
            "test2",
            user1,
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 86400
        );

        address tokenObserverSetter = makeAddr("tokenObserverSetter");

        // Grant the SET_TOKEN_OBSERVER role specifically for this token to a non-owner
        registry.grantRoles(
            registry.testGetResourceFromTokenId(tokenId),
            LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER,
            tokenObserverSetter
        );

        // Verify the role was granted
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER,
                tokenObserverSetter
            )
        );

        uint256 newTokenId = registry.testGetTokenIdFromResource(
            registry.testGetResourceFromTokenId(tokenId)
        );

        // The non-owner with role should be able to set the token observer
        vm.prank(tokenObserverSetter);
        registry.setTokenObserver(newTokenId, observer);

        // Verify observer was set
        assertEq(
            address(registry.tokenObservers(newTokenId)),
            address(observer)
        );
    }

    function test_Revert_renew_when_token_observer_reverts() public {
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 100
        );
        registry.setTokenObserver(tokenId, revertingObserver);

        uint64 newExpiry = uint64(block.timestamp) + 200;
        vm.expectRevert(RevertingTokenObserver.ObserverReverted.selector);
        registry.renew(tokenId, newExpiry);

        uint64 expiry = registry.getExpiry(tokenId);
        assertEq(expiry, uint64(block.timestamp) + 100);
    }

    function test_set_token_observer_emits_event() public {
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 100
        );

        vm.recordLogs();
        registry.setTokenObserver(tokenId, observer);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(
            entries[0].topics[0],
            keccak256("TokenObserverSet(uint256,address)")
        );
        assertEq(entries[0].topics[1], bytes32(tokenId));
        address observerAddress = abi.decode(entries[0].data, (address));
        assertEq(observerAddress, address(observer));
    }

    function test_expired_name_reregistration_resets_roles() public {
        // Register a name with owner1
        address owner1 = makeAddr("owner1");
        uint256 tokenId = registry.register(
            "resettest",
            owner1,
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 100
        );

        // Grant an additional role to owner1
        registry.grantRoles(
            registry.testGetResourceFromTokenId(tokenId),
            LibRegistryRoles.ROLE_RENEW,
            owner1
        );

        // Verify owner1 has roles
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_SUBREGISTRY,
                owner1
            )
        );
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_RESOLVER,
                owner1
            )
        );
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER,
                owner1
            )
        );
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_RENEW,
                owner1
            )
        );

        uint256 originalResourceId = registry.testGetResourceFromTokenId(
            tokenId
        );

        // Move time forward to expire the name
        vm.warp(block.timestamp + 101);

        // Verify token is expired
        assertEq(registry.ownerOf(tokenId), address(0));

        // Re-register with owner2
        address owner2 = makeAddr("owner2");
        uint256 newTokenId = registry.register(
            "resettest",
            owner2,
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 100
        );

        // Verify it's a different token ID
        assertNotEq(
            newTokenId,
            tokenId,
            "Token ID should change after re-registration"
        );
        uint256 newResourceId = registry.testGetResourceFromTokenId(newTokenId);
        assertEq(
            newResourceId,
            originalResourceId,
            "Resource ID should NOT change after re-registration"
        );

        // owner1 should no longer have roles for this token
        // Test specifically using new resource ID
        assertFalse(
            registry.hasRoles(
                newResourceId,
                LibRegistryRoles.ROLE_SET_SUBREGISTRY,
                owner1
            )
        );
        assertFalse(
            registry.hasRoles(
                newResourceId,
                LibRegistryRoles.ROLE_SET_RESOLVER,
                owner1
            )
        );
        assertFalse(
            registry.hasRoles(
                newResourceId,
                LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER,
                owner1
            )
        );
        assertFalse(
            registry.hasRoles(
                newResourceId,
                LibRegistryRoles.ROLE_RENEW,
                owner1
            )
        );

        // And owner2 should have the default roles
        assertTrue(
            registry.hasRoles(
                newResourceId,
                LibRegistryRoles.ROLE_SET_SUBREGISTRY,
                owner2
            )
        );
        assertTrue(
            registry.hasRoles(
                newResourceId,
                LibRegistryRoles.ROLE_SET_RESOLVER,
                owner2
            )
        );
        assertTrue(
            registry.hasRoles(
                newResourceId,
                LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER,
                owner2
            )
        );
    }

    function test_token_transfer_also_transfers_roles() public {
        // Register a name with owner1
        address owner1 = makeAddr("owner1");
        uint256 tokenId = registry.register(
            "transfertest",
            owner1,
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 100
        );

        // Capture the resource ID before transfer
        uint256 originalResourceId = registry.testGetResourceFromTokenId(
            tokenId
        );

        // Grant additional role to owner1
        registry.grantRoles(
            originalResourceId,
            LibRegistryRoles.ROLE_RENEW,
            owner1
        );

        // get the new token id
        uint256 newTokenId = registry.testGetTokenIdFromResource(
            originalResourceId
        );

        // Verify owner1 has roles
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(newTokenId),
                LibRegistryRoles.ROLE_SET_SUBREGISTRY,
                owner1
            )
        );
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(newTokenId),
                LibRegistryRoles.ROLE_SET_RESOLVER,
                owner1
            )
        );
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(newTokenId),
                LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER,
                owner1
            )
        );
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(newTokenId),
                LibRegistryRoles.ROLE_RENEW,
                owner1
            )
        );

        // Transfer to owner2
        address owner2 = makeAddr("owner2");
        vm.prank(owner1);
        registry.safeTransferFrom(owner1, owner2, newTokenId, 1, "");

        // Verify token ownership transferred
        assertEq(registry.ownerOf(newTokenId), owner2);

        // Verify the resource ID has not changed
        uint256 newResourceId = registry.testGetResourceFromTokenId(newTokenId);
        assertEq(
            newResourceId,
            originalResourceId,
            "Resource ID should be the same"
        );

        // Check using the new resource ID that owner1 no longer has roles
        assertFalse(
            registry.hasRoles(
                newResourceId,
                LibRegistryRoles.ROLE_SET_SUBREGISTRY,
                owner1
            )
        );
        assertFalse(
            registry.hasRoles(
                newResourceId,
                LibRegistryRoles.ROLE_SET_RESOLVER,
                owner1
            )
        );
        assertFalse(
            registry.hasRoles(
                newResourceId,
                LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER,
                owner1
            )
        );
        assertFalse(
            registry.hasRoles(
                newResourceId,
                LibRegistryRoles.ROLE_RENEW,
                owner1
            )
        );

        // New owner should automatically receive any roles after transfer
        assertTrue(
            registry.hasRoles(
                newResourceId,
                LibRegistryRoles.ROLE_SET_SUBREGISTRY,
                owner2
            )
        );
        assertTrue(
            registry.hasRoles(
                newResourceId,
                LibRegistryRoles.ROLE_SET_RESOLVER,
                owner2
            )
        );
        assertTrue(
            registry.hasRoles(
                newResourceId,
                LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER,
                owner2
            )
        );
        assertTrue(
            registry.hasRoles(
                newResourceId,
                LibRegistryRoles.ROLE_RENEW,
                owner2
            )
        );
    }

    function test_Revert_setTokenObserver_when_token_expired() public {
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 100
        );

        vm.warp(block.timestamp + 101);

        vm.expectRevert(
            abi.encodeWithSelector(
                IStandardRegistry.NameExpired.selector,
                tokenId
            )
        );
        registry.setTokenObserver(tokenId, observer);
    }

    function test_Revert_setSubregistry_when_token_expired() public {
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 100
        );

        vm.warp(block.timestamp + 101);

        vm.expectRevert(
            abi.encodeWithSelector(
                IStandardRegistry.NameExpired.selector,
                tokenId
            )
        );
        registry.setSubregistry(tokenId, IRegistry(address(this)));
    }

    function test_Revert_setResolver_when_token_expired() public {
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 100
        );

        vm.warp(block.timestamp + 101);

        vm.expectRevert(
            abi.encodeWithSelector(
                IStandardRegistry.NameExpired.selector,
                tokenId
            )
        );
        registry.setResolver(tokenId, address(this));
    }

    function test_Revert_setTokenObserver_without_role_when_expired() public {
        uint256 tokenId = registry.register(
            "test2",
            user1,
            registry,
            address(0),
            noRolesRoleBitmap,
            uint64(block.timestamp) + 100
        );

        vm.warp(block.timestamp + 101);

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER,
                user1
            )
        );
        vm.prank(user1);
        registry.setTokenObserver(tokenId, observer);
    }

    function test_Revert_setSubregistry_without_role_when_expired() public {
        uint256 tokenId = registry.register(
            "test2",
            user1,
            registry,
            address(0),
            noRolesRoleBitmap,
            uint64(block.timestamp) + 100
        );

        vm.warp(block.timestamp + 101);

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_SUBREGISTRY,
                user1
            )
        );
        vm.prank(user1);
        registry.setSubregistry(tokenId, IRegistry(address(this)));
    }

    function test_Revert_setResolver_without_role_when_expired() public {
        uint256 tokenId = registry.register(
            "test2",
            user1,
            registry,
            address(0),
            noRolesRoleBitmap,
            uint64(block.timestamp) + 100
        );

        vm.warp(block.timestamp + 101);

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_RESOLVER,
                user1
            )
        );
        vm.prank(user1);
        registry.setResolver(tokenId, address(this));
    }

    function test_setTokenObserver_with_role_when_not_expired() public {
        uint256 tokenId = registry.register(
            "test2",
            user1,
            registry,
            address(0),
            LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER,
            uint64(block.timestamp) + 100
        );

        vm.prank(user1);
        registry.setTokenObserver(tokenId, observer);

        assertEq(address(registry.tokenObservers(tokenId)), address(observer));
    }

    function test_setSubregistry_with_role_when_not_expired() public {
        uint256 tokenId = registry.register(
            "test2",
            user1,
            registry,
            address(0),
            LibRegistryRoles.ROLE_SET_SUBREGISTRY,
            uint64(block.timestamp) + 100
        );

        vm.prank(user1);
        registry.setSubregistry(tokenId, IRegistry(address(this)));

        assertEq(address(registry.getSubregistry("test2")), address(this));
    }

    function test_setResolver_with_role_when_not_expired() public {
        uint256 tokenId = registry.register(
            "test2",
            user1,
            registry,
            address(0),
            LibRegistryRoles.ROLE_SET_RESOLVER,
            uint64(block.timestamp) + 100
        );

        vm.prank(user1);
        registry.setResolver(tokenId, address(this));

        assertEq(registry.getResolver("test2"), address(this));
    }

    function test_Revert_setTokenObserver_without_role_when_not_expired()
        public
    {
        uint256 tokenId = registry.register(
            "test2",
            user1,
            registry,
            address(0),
            noRolesRoleBitmap,
            uint64(block.timestamp) + 100
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER,
                user1
            )
        );
        vm.prank(user1);
        registry.setTokenObserver(tokenId, observer);
    }

    function test_Revert_setSubregistry_without_role_when_not_expired() public {
        uint256 tokenId = registry.register(
            "test2",
            user1,
            registry,
            address(0),
            noRolesRoleBitmap,
            uint64(block.timestamp) + 100
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_SUBREGISTRY,
                user1
            )
        );
        vm.prank(user1);
        registry.setSubregistry(tokenId, IRegistry(address(this)));
    }

    function test_Revert_setResolver_without_role_when_not_expired() public {
        uint256 tokenId = registry.register(
            "test2",
            user1,
            registry,
            address(0),
            noRolesRoleBitmap,
            uint64(block.timestamp) + 100
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.testGetResourceFromTokenId(tokenId),
                LibRegistryRoles.ROLE_SET_RESOLVER,
                user1
            )
        );
        vm.prank(user1);
        registry.setResolver(tokenId, address(this));
    }

    function test_token_regeneration_on_role_grant() public {
        // Register a token with owner1
        address owner1 = makeAddr("owner1");
        uint256 tokenId = registry.register(
            "regenerate1",
            owner1,
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 100
        );

        // Record the resource ID (should remain stable)
        uint256 resourceId = registry.testGetResourceFromTokenId(tokenId);

        // Grant a new role to another user
        address user2 = makeAddr("user2");

        vm.recordLogs();
        registry.grantRoles(resourceId, LibRegistryRoles.ROLE_RENEW, user2);

        // Check for the TokenRegenerated event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundEvent = false;
        uint256 newTokenId;

        for (uint i = 0; i < entries.length; i++) {
            if (
                entries[i].topics[0] ==
                keccak256("TokenRegenerated(uint256,uint256)")
            ) {
                foundEvent = true;
                uint256 oldTokenIdFromEvent;
                (oldTokenIdFromEvent, newTokenId) = abi.decode(
                    entries[i].data,
                    (uint256, uint256)
                );
                assertEq(
                    oldTokenIdFromEvent,
                    tokenId,
                    "Old token ID in event doesn't match"
                );
                break;
            }
        }

        assertTrue(foundEvent, "TokenRegenerated event not emitted");
        assertNotEq(newTokenId, tokenId, "Token ID should have changed");

        // Check that the new token ID has the same resource ID
        assertEq(
            registry.testGetResourceFromTokenId(newTokenId),
            resourceId,
            "Resource ID should remain the same"
        );

        // Verify the owner still owns the token (new token ID)
        assertEq(registry.ownerOf(newTokenId), owner1);

        // Verify the owner still has the same permissions
        assertTrue(
            registry.hasRoles(
                resourceId,
                LibRegistryRoles.ROLE_SET_SUBREGISTRY,
                owner1
            )
        );
        assertTrue(
            registry.hasRoles(
                resourceId,
                LibRegistryRoles.ROLE_SET_RESOLVER,
                owner1
            )
        );
        assertTrue(
            registry.hasRoles(
                resourceId,
                LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER,
                owner1
            )
        );

        // Verify the granted role exists on the resource
        assertTrue(
            registry.hasRoles(resourceId, LibRegistryRoles.ROLE_RENEW, user2)
        );
    }

    function test_token_regeneration_on_role_revoke() public {
        // Register a token with owner1
        address owner1 = makeAddr("owner1");
        uint256 tokenId = registry.register(
            "regenerate2",
            owner1,
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 100
        );

        // Record the resource ID (should remain stable)
        uint256 resourceId = registry.testGetResourceFromTokenId(tokenId);

        // Grant a role to another user first
        address user2 = makeAddr("user2");
        registry.grantRoles(resourceId, LibRegistryRoles.ROLE_RENEW, user2);

        // Get the new token ID after first regeneration
        uint256 intermediateTokenId = registry.testGetTokenIdFromResource(
            resourceId
        );

        // Now revoke the role and check regeneration again
        vm.recordLogs();
        registry.revokeRoles(resourceId, LibRegistryRoles.ROLE_RENEW, user2);

        // Check for the TokenRegenerated event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundEvent = false;
        uint256 newTokenId;

        for (uint i = 0; i < entries.length; i++) {
            if (
                entries[i].topics[0] ==
                keccak256("TokenRegenerated(uint256,uint256)")
            ) {
                foundEvent = true;
                uint256 oldTokenIdFromEvent;
                (oldTokenIdFromEvent, newTokenId) = abi.decode(
                    entries[i].data,
                    (uint256, uint256)
                );
                assertEq(
                    oldTokenIdFromEvent,
                    intermediateTokenId,
                    "Old token ID in event doesn't match"
                );
                break;
            }
        }

        assertTrue(foundEvent, "TokenRegenerated event not emitted");
        assertNotEq(
            newTokenId,
            intermediateTokenId,
            "Token ID should have changed"
        );
        assertNotEq(
            newTokenId,
            tokenId,
            "Token ID should not revert to original"
        );

        // Check that the new token ID has the same resource ID
        assertEq(
            registry.testGetResourceFromTokenId(newTokenId),
            resourceId,
            "Resource ID should remain the same"
        );

        // Verify the owner still owns the token (new token ID)
        assertEq(registry.ownerOf(newTokenId), owner1);

        // Verify the owner still has the same permissions
        assertTrue(
            registry.hasRoles(
                resourceId,
                LibRegistryRoles.ROLE_SET_SUBREGISTRY,
                owner1
            )
        );
        assertTrue(
            registry.hasRoles(
                resourceId,
                LibRegistryRoles.ROLE_SET_RESOLVER,
                owner1
            )
        );
        assertTrue(
            registry.hasRoles(
                resourceId,
                LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER,
                owner1
            )
        );

        // Verify the revoked role is gone
        assertFalse(
            registry.hasRoles(resourceId, LibRegistryRoles.ROLE_RENEW, user2)
        );
    }

    function test_maintaining_owner_roles_across_regenerations() public {
        // Register a token with owner1
        address owner1 = makeAddr("owner1");
        uint256 tokenId = registry.register(
            "regenerate3",
            owner1,
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 100
        );

        // Record the resource ID (should remain stable)
        uint256 resourceId = registry.testGetResourceFromTokenId(tokenId);

        // Grant an additional role to the owner
        registry.grantRoles(resourceId, LibRegistryRoles.ROLE_RENEW, owner1);

        // Get the new token ID after regeneration
        uint256 intermediateTokenId = registry.testGetTokenIdFromResource(
            resourceId
        );

        // Now grant a role to another user, triggering another regeneration
        address user2 = makeAddr("user2");
        registry.grantRoles(resourceId, LibRegistryRoles.ROLE_RENEW, user2);

        // Get the final token ID
        uint256 finalTokenId = registry.testGetTokenIdFromResource(resourceId);

        // Verify the token has been regenerated twice
        assertNotEq(
            tokenId,
            intermediateTokenId,
            "Token should be regenerated first time"
        );
        assertNotEq(
            intermediateTokenId,
            finalTokenId,
            "Token should be regenerated second time"
        );

        // Verify the owner still owns the token (new token ID)
        assertEq(
            registry.ownerOf(finalTokenId),
            owner1,
            "still owns the token"
        );

        // Verify the owner still has ALL the permissions
        assertTrue(
            registry.hasRoles(
                resourceId,
                LibRegistryRoles.ROLE_SET_SUBREGISTRY,
                owner1
            )
        );
        assertTrue(
            registry.hasRoles(
                resourceId,
                LibRegistryRoles.ROLE_SET_RESOLVER,
                owner1
            )
        );
        assertTrue(
            registry.hasRoles(
                resourceId,
                LibRegistryRoles.ROLE_SET_TOKEN_OBSERVER,
                owner1
            )
        );
        assertTrue(
            registry.hasRoles(resourceId, LibRegistryRoles.ROLE_RENEW, owner1)
        );

        // Verify the other user has their role
        assertTrue(
            registry.hasRoles(resourceId, LibRegistryRoles.ROLE_RENEW, user2)
        );
    }

    function test_token_regeneration_mostRecentOwnerOf() public {
        address user = makeAddr("user");
        uint256 tokenId = registry.register(
            "regenerate4",
            user,
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 100
        );
        uint256 resourceId = registry.testGetResourceFromTokenId(tokenId);
        registry.grantRoles(resourceId, LibRegistryRoles.ROLE_RENEW, user);
        uint256 newTokenId = registry.testGetTokenIdFromResource(resourceId);
        assertNotEq(tokenId, newTokenId, "token");
        vm.warp(block.timestamp + 101);
        assertEq(registry.ownerOf(tokenId), address(0), "owner0");
        assertEq(registry.mostRecentOwnerOf(tokenId), address(0), "recent0");
        assertEq(registry.ownerOf(newTokenId), address(0), "owner1");
        assertEq(registry.mostRecentOwnerOf(newTokenId), user, "recent1");
    }

    // getRoleAssigneeCount tests

    function test_getRoleAssigneeCount_single_role_single_assignee() public {
        uint256 tokenId = registry.register(
            "counttest1",
            user1,
            registry,
            address(0),
            LibRegistryRoles.ROLE_SET_RESOLVER,
            uint64(block.timestamp) + 86400
        );

        (uint256 counts, ) = registry.getAssigneeCount(
            tokenId,
            LibRegistryRoles.ROLE_SET_RESOLVER
        );

        // ROLE_SET_RESOLVER is 1 << 12, so count of 1 should be at bit position 12
        uint256 expectedCount = 1 << 12;
        assertEq(
            counts,
            expectedCount,
            "Should have count of 1 for SET_RESOLVER role"
        );
    }

    function test_getRoleAssigneeCount_single_role_multiple_assignees() public {
        uint256 tokenId = registry.register(
            "counttest2",
            user1,
            registry,
            address(0),
            LibRegistryRoles.ROLE_SET_RESOLVER,
            uint64(block.timestamp) + 86400
        );

        // Grant the same role to additional users
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        uint256 resourceId = registry.testGetResourceFromTokenId(tokenId);
        registry.grantRoles(
            resourceId,
            LibRegistryRoles.ROLE_SET_RESOLVER,
            user2
        );
        registry.grantRoles(
            resourceId,
            LibRegistryRoles.ROLE_SET_RESOLVER,
            user3
        );

        // Get the updated token ID after regenerations
        uint256 currentTokenId = registry.testGetTokenIdFromResource(
            resourceId
        );

        (uint256 counts, ) = registry.getAssigneeCount(
            currentTokenId,
            LibRegistryRoles.ROLE_SET_RESOLVER
        );

        // Should have count of 3 at bit position 12
        uint256 expectedCount = 3 << 12;
        assertEq(
            counts,
            expectedCount,
            "Should have count of 3 for SET_RESOLVER role"
        );
    }

    function test_getRoleAssigneeCount_single_role_no_assignees() public {
        uint256 tokenId = registry.register(
            "counttest3",
            user1,
            registry,
            address(0),
            LibRegistryRoles.ROLE_SET_RESOLVER,
            uint64(block.timestamp) + 86400
        );

        (uint256 counts, ) = registry.getAssigneeCount(
            tokenId,
            LibRegistryRoles.ROLE_RENEW
        );

        assertEq(counts, 0, "Should have count of 0 for unassigned RENEW role");
    }

    function test_getRoleAssigneeCount_multiple_roles_mixed_assignees() public {
        uint256 tokenId = registry.register(
            "counttest4",
            user1,
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 86400
        );

        // Grant additional roles to different users
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        uint256 resourceId = registry.testGetResourceFromTokenId(tokenId);
        registry.grantRoles(
            resourceId,
            LibRegistryRoles.ROLE_SET_RESOLVER,
            user2
        );
        registry.grantRoles(resourceId, LibRegistryRoles.ROLE_RENEW, user2);
        registry.grantRoles(resourceId, LibRegistryRoles.ROLE_RENEW, user3);

        // Get the updated token ID after regenerations
        uint256 currentTokenId = registry.testGetTokenIdFromResource(
            resourceId
        );

        // Query for SET_RESOLVER and RENEW roles
        uint256 queryBitmap = LibRegistryRoles.ROLE_SET_RESOLVER |
            LibRegistryRoles.ROLE_RENEW;
        (uint256 counts, ) = registry.getAssigneeCount(
            currentTokenId,
            queryBitmap
        );

        // user1 has SET_RESOLVER (from defaultRoleBitmap), user2 has SET_RESOLVER + RENEW, user3 has RENEW
        // SET_RESOLVER (1<<12): 2 assignees -> 2 << 12
        // RENEW (1<<4): 2 assignees -> 2 << 4
        uint256 expectedCount = (2 << 12) | (2 << 4);
        assertEq(
            counts,
            expectedCount,
            "Should have correct counts for both roles"
        );
    }

    function test_getRoleAssigneeCount_multiple_roles_partial_assignees()
        public
    {
        uint256 tokenId = registry.register(
            "counttest5",
            user1,
            registry,
            address(0),
            LibRegistryRoles.ROLE_SET_RESOLVER,
            uint64(block.timestamp) + 86400
        );

        // Query for multiple roles where only SET_RESOLVER has assignees
        uint256 queryBitmap = LibRegistryRoles.ROLE_SET_RESOLVER |
            LibRegistryRoles.ROLE_RENEW |
            LibRegistryRoles.ROLE_BURN;
        (uint256 counts, ) = registry.getAssigneeCount(tokenId, queryBitmap);

        // Only SET_RESOLVER should have 1 assignee
        uint256 expectedCount = 1 << 12;
        assertEq(
            counts,
            expectedCount,
            "Should have count only for SET_RESOLVER"
        );
    }

    function test_getRoleAssigneeCount_all_default_roles() public {
        uint256 tokenId = registry.register(
            "counttest6",
            user1,
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 86400
        );

        (uint256 counts, ) = registry.getAssigneeCount(
            tokenId,
            defaultRoleBitmap
        );

        // defaultRoleBitmap includes SET_SUBREGISTRY (1<<8), SET_RESOLVER (1<<12), SET_TOKEN_OBSERVER (1<<16)
        // Each should have 1 assignee
        uint256 expectedCount = (1 << 8) | (1 << 12) | (1 << 16);
        assertEq(
            counts,
            expectedCount,
            "Should have count of 1 for each default role"
        );
    }

    function test_getRoleAssigneeCount_overlapping_role_assignments() public {
        uint256 tokenId = registry.register(
            "counttest7",
            user1,
            registry,
            address(0),
            LibRegistryRoles.ROLE_SET_RESOLVER,
            uint64(block.timestamp) + 86400
        );

        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        uint256 resourceId = registry.testGetResourceFromTokenId(tokenId);

        // Grant overlapping roles
        registry.grantRoles(
            resourceId,
            LibRegistryRoles.ROLE_SET_RESOLVER | LibRegistryRoles.ROLE_RENEW,
            user2
        );
        registry.grantRoles(
            resourceId,
            LibRegistryRoles.ROLE_RENEW | LibRegistryRoles.ROLE_BURN,
            user3
        );

        // Get the updated token ID after regenerations
        uint256 currentTokenId = registry.testGetTokenIdFromResource(
            resourceId
        );

        // Query for all three roles
        uint256 queryBitmap = LibRegistryRoles.ROLE_SET_RESOLVER |
            LibRegistryRoles.ROLE_RENEW |
            LibRegistryRoles.ROLE_BURN;
        (uint256 counts, ) = registry.getAssigneeCount(
            currentTokenId,
            queryBitmap
        );

        // user1: SET_RESOLVER
        // user2: SET_RESOLVER, RENEW
        // user3: RENEW, BURN
        // SET_RESOLVER (1<<12): 2 assignees -> 2 << 12
        // RENEW (1<<4): 2 assignees -> 2 << 4
        // BURN (1<<20): 1 assignee -> 1 << 20
        uint256 expectedCount = (2 << 12) | (2 << 4) | (1 << 20);
        assertEq(
            counts,
            expectedCount,
            "Should have correct counts for all roles"
        );
    }

    function test_getRoleAssigneeCount_after_role_revocation() public {
        uint256 tokenId = registry.register(
            "counttest8",
            user1,
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 86400
        );

        address user2 = makeAddr("user2");
        uint256 resourceId = registry.testGetResourceFromTokenId(tokenId);

        // Grant role to user2
        registry.grantRoles(
            resourceId,
            LibRegistryRoles.ROLE_SET_RESOLVER,
            user2
        );
        uint256 tokenIdAfterGrant = registry.testGetTokenIdFromResource(
            resourceId
        );

        // Check count before revocation - should have 2 assignees for SET_RESOLVER
        (uint256 countsBefore, ) = registry.getAssigneeCount(
            tokenIdAfterGrant,
            LibRegistryRoles.ROLE_SET_RESOLVER
        );
        uint256 expectedCountBefore = 2 << 12;
        assertEq(
            countsBefore,
            expectedCountBefore,
            "Should have 2 assignees before revocation"
        );

        // Revoke role from user2
        registry.revokeRoles(
            resourceId,
            LibRegistryRoles.ROLE_SET_RESOLVER,
            user2
        );
        uint256 tokenIdAfterRevoke = registry.testGetTokenIdFromResource(
            resourceId
        );

        // Check count after revocation - should have 1 assignee for SET_RESOLVER
        (uint256 countsAfter, ) = registry.getAssigneeCount(
            tokenIdAfterRevoke,
            LibRegistryRoles.ROLE_SET_RESOLVER
        );
        uint256 expectedCountAfter = 1 << 12;
        assertEq(
            countsAfter,
            expectedCountAfter,
            "Should have 1 assignee after revocation"
        );
    }

    function test_getRoleAssigneeCount_zero_bitmap() public {
        uint256 tokenId = registry.register(
            "counttest9",
            user1,
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 86400
        );

        (uint256 counts, ) = registry.getAssigneeCount(tokenId, 0);

        assertEq(counts, 0, "Should have 0 counts for empty bitmap");
    }

    function test_transfer_succeeds_with_max_assignees_BET_430() public {
        // Register a token with default roles
        address tokenOwner = makeAddr("tokenOwner");
        uint256 tokenId = registry.register(
            "maxtransfertest",
            tokenOwner,
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 86400
        );

        uint256 resourceId = registry.testGetResourceFromTokenId(tokenId);

        // Create 14 additional addresses and grant them the same role as the token owner has
        address[] memory additionalUsers = new address[](14);
        for (uint256 i = 0; i < 14; i++) {
            additionalUsers[i] = makeAddr(
                string(abi.encodePacked("maxUser", i))
            );
            // Grant ROLE_SET_RESOLVER to reach max assignees (owner + 14 others = 15 total)
            registry.grantRoles(
                resourceId,
                LibRegistryRoles.ROLE_SET_RESOLVER,
                additionalUsers[i]
            );
        }

        // Get the current token ID after role grants (which may have triggered regeneration)
        uint256 currentTokenId = registry.testGetTokenIdFromResource(
            resourceId
        );

        // Verify we have 15 assignees for ROLE_SET_RESOLVER (max allowed)
        (uint256 counts, ) = registry.getAssigneeCount(
            currentTokenId,
            LibRegistryRoles.ROLE_SET_RESOLVER
        );
        uint256 expectedCount = 15 << 12; // ROLE_SET_RESOLVER is at bit 12, so count goes to position 12
        assertEq(
            counts,
            expectedCount,
            "Should have 15 assignees for ROLE_SET_RESOLVER"
        );

        // Now attempt to transfer the token to a new address
        address newOwner = makeAddr("newTokenOwner");

        // This transfer should NOT fail even though we're at max assignees
        vm.prank(tokenOwner);
        registry.safeTransferFrom(tokenOwner, newOwner, currentTokenId, 1, "");

        // Verify the transfer succeeded
        assertEq(
            registry.ownerOf(currentTokenId),
            newOwner,
            "Token should be transferred to new owner"
        );

        // Verify the new owner has the roles
        assertTrue(
            registry.hasRoles(
                resourceId,
                LibRegistryRoles.ROLE_SET_RESOLVER,
                newOwner
            ),
            "New owner should have ROLE_SET_RESOLVER"
        );

        // Verify the old owner no longer has roles
        assertFalse(
            registry.hasRoles(
                resourceId,
                LibRegistryRoles.ROLE_SET_RESOLVER,
                tokenOwner
            ),
            "Old owner should no longer have ROLE_SET_RESOLVER"
        );

        // Verify we still have 15 total assignees (the 14 additional users + new owner)
        (uint256 countsAfter, ) = registry.getAssigneeCount(
            currentTokenId,
            LibRegistryRoles.ROLE_SET_RESOLVER
        );
        assertEq(
            countsAfter,
            expectedCount,
            "Should still have 15 assignees after transfer"
        );
    }

    function test_getRoleAssigneeCount_nonexistent_role() public {
        uint256 tokenId = registry.register(
            "counttest10",
            user1,
            registry,
            address(0),
            defaultRoleBitmap,
            uint64(block.timestamp) + 86400
        );

        // Use a role that doesn't exist in the registry roles
        uint256 nonexistentRole = 1 << 24; // Role at bit 24
        (uint256 counts, ) = registry.getAssigneeCount(
            tokenId,
            nonexistentRole
        );

        assertEq(counts, 0, "Should have 0 counts for nonexistent role");
    }
}

contract MockTokenObserver is ITokenObserver {
    uint256 public lastTokenId;
    uint64 public lastExpiry;
    address public lastCaller;

    function onRenew(
        uint256 tokenId,
        uint64 expires,
        address renewedBy
    ) external {
        lastTokenId = tokenId;
        lastExpiry = expires;
        lastCaller = renewedBy;
    }
}

contract RevertingTokenObserver is ITokenObserver {
    error ObserverReverted();

    function onRenew(uint256, uint64, address) external pure {
        revert ObserverReverted();
    }
}
