// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering, one-contract-per-file

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {EACBaseRolesLib} from "~src/common/access-control/EnhancedAccessControl.sol";
import {
    IEnhancedAccessControl
} from "~src/common/access-control/interfaces/IEnhancedAccessControl.sol";
import {IRegistry} from "~src/common/registry/interfaces/IRegistry.sol";
import {IRegistryDatastore} from "~src/common/registry/interfaces/IRegistryDatastore.sol";
import {IRegistryMetadata} from "~src/common/registry/interfaces/IRegistryMetadata.sol";
import {IStandardRegistry} from "~src/common/registry/interfaces/IStandardRegistry.sol";
import {ITokenObserver} from "~src/common/registry/interfaces/ITokenObserver.sol";
import {RegistryRolesLib} from "~src/common/registry/libraries/RegistryRolesLib.sol";
import {RegistryDatastore} from "~src/common/registry/RegistryDatastore.sol";
import {SimpleRegistryMetadata} from "~src/common/registry/SimpleRegistryMetadata.sol";
import {LibLabel} from "~src/common/utils/LibLabel.sol";
import {MockPermissionedRegistry} from "~test/mocks/MockPermissionedRegistry.sol";

contract PermissionedRegistryTest is Test, ERC1155Holder {
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

    uint256 constant DEFAULT_ROLE_BITMAP =
        RegistryRolesLib.ROLE_SET_SUBREGISTRY |
            RegistryRolesLib.ROLE_SET_RESOLVER |
            RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER;
    uint256 constant LOCKED_RESOLVER_ROLE_BITMAP =
        RegistryRolesLib.ROLE_SET_SUBREGISTRY | RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER;
    uint256 constant LOCKED_SUBREGISTRY_ROLE_BITMAP =
        RegistryRolesLib.ROLE_SET_RESOLVER | RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER;
    uint256 constant NO_ROLES_ROLE_BITMAP = 0;

    address user1 = makeAddr("user1");

    // all roles
    uint256 deployerRoles = EACBaseRolesLib.ALL_ROLES;

    function setUp() public {
        datastore = new RegistryDatastore();
        metadata = new SimpleRegistryMetadata();
        registry = new MockPermissionedRegistry(datastore, metadata, address(this), deployerRoles);
        observer = new MockTokenObserver();
        revertingObserver = new RevertingTokenObserver();
    }

    function test_constructor_sets_roles() public view {
        uint256 expectedRoles = deployerRoles;
        assertTrue(registry.hasRoles(registry.ROOT_RESOURCE(), expectedRoles, address(this)));
    }

    function test_Revert_register_without_registrar_role() public {
        address nonRegistrar = makeAddr("nonRegistrar");

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.ROOT_RESOURCE(),
                RegistryRolesLib.ROLE_REGISTRAR,
                nonRegistrar
            )
        );
        vm.prank(nonRegistrar);
        registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );
    }

    function test_Revert_renew_without_renew_role() public {
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        address nonRenewer = makeAddr("nonRenewer");

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_RENEW,
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
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        address tokenRenewer = makeAddr("tokenRenewer");

        // Grant the RENEW role specifically for this token
        registry.grantRoles(
            registry.testGetResourceFromTokenId(tokenId),
            RegistryRolesLib.ROLE_RENEW,
            tokenRenewer
        );

        // Verify the role was granted
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_RENEW,
                tokenRenewer
            )
        );

        // This user doesn't have the ROOT_RESOURCE RegistryRolesLib.ROLE_RENEW
        assertFalse(
            registry.hasRoles(registry.ROOT_RESOURCE(), RegistryRolesLib.ROLE_RENEW, tokenRenewer)
        );

        // But should still be able to renew this specific token
        vm.prank(tokenRenewer);
        uint64 newExpiry = uint64(block.timestamp) + 172800;
        registry.renew(tokenId, newExpiry);

        uint64 expiry = registry.getExpiry(tokenId);
        assertEq(expiry, newExpiry);
    }

    function test_token_owner_can_renew_if_granted_role() public {
        // Register a token with specific roles including RegistryRolesLib.ROLE_RENEW
        uint256 roleBitmap = DEFAULT_ROLE_BITMAP | RegistryRolesLib.ROLE_RENEW;
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
                RegistryRolesLib.ROLE_RENEW,
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
            NO_ROLES_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        // Verify the owner doesn't have the RENEW role for this token (this is the intent of the test)
        assertFalse(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_RENEW,
                tokenOwner
            )
        );

        // Owner should not be able to renew without the role
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_RENEW,
                tokenOwner
            )
        );
        vm.prank(tokenOwner);
        registry.renew(tokenId, uint64(block.timestamp) + 172800);
    }

    function test_registrar_can_register() public {
        address registrar2 = makeAddr("registrar");
        registry.grantRootRoles(RegistryRolesLib.ROLE_REGISTRAR, registrar2);

        vm.prank(registrar2);
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
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
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        address renewer = makeAddr("renewer");
        registry.grantRootRoles(RegistryRolesLib.ROLE_RENEW, renewer);

        vm.prank(renewer);
        uint64 newExpiry = uint64(block.timestamp) + 172800;
        registry.renew(tokenId, newExpiry);

        uint64 expiry = registry.getExpiry(tokenId);
        assertEq(expiry, newExpiry);
    }

    function test_register_unlocked() public {
        uint256 tokenId = registry.register(
            "test2",
            user1,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        // Verify roles
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_SUBREGISTRY,
                user1
            )
        );
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_RESOLVER,
                user1
            )
        );
    }

    function test_register_locked() public {
        uint256 tokenId = registry.register(
            "test2",
            user1,
            registry,
            address(0),
            NO_ROLES_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        // Verify roles
        assertFalse(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_SUBREGISTRY,
                user1
            )
        );
        assertFalse(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_RESOLVER,
                user1
            )
        );
    }

    function test_register_locked_subregistry() public {
        uint256 tokenId = registry.register(
            "test2",
            user1,
            registry,
            address(0),
            LOCKED_SUBREGISTRY_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        // Verify roles
        assertFalse(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_SUBREGISTRY,
                user1
            )
        );
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_RESOLVER,
                user1
            )
        );
    }

    function test_register_locked_resolver() public {
        uint256 tokenId = registry.register(
            "test2",
            user1,
            registry,
            address(0),
            LOCKED_RESOLVER_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        // Verify roles
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_SUBREGISTRY,
                user1
            )
        );
        assertFalse(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_RESOLVER,
                user1
            )
        );
    }

    function test_Revert_cannot_mint_duplicates() public {
        registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        vm.expectRevert(
            abi.encodeWithSelector(IStandardRegistry.NameAlreadyRegistered.selector, "test2")
        );
        registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );
    }

    function test_set_subregistry() public {
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
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
            LOCKED_SUBREGISTRY_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_SUBREGISTRY,
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
            DEFAULT_ROLE_BITMAP,
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
            LOCKED_RESOLVER_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_RESOLVER,
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
            DEFAULT_ROLE_BITMAP,
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
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );
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
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );
        vm.warp(block.timestamp + 101);

        vm.expectRevert(abi.encodeWithSelector(IStandardRegistry.NameExpired.selector, tokenId));
        registry.renew(tokenId, uint64(block.timestamp) + 200);
    }

    function test_Revert_renew_reduce_expiry() public {
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
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
        uint256 roleBitmap = DEFAULT_ROLE_BITMAP | RegistryRolesLib.ROLE_BURN;
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
        vm.assertEq(address(registry.getSubregistry("test2")), address(0), "registry");
        vm.assertEq(registry.latestOwnerOf(tokenId), address(0), "latest"); // does not survive burn
    }

    function test_burn_revokes_roles() public {
        uint256 roleBitmap = DEFAULT_ROLE_BITMAP | RegistryRolesLib.ROLE_BURN;
        uint256 tokenId = registry.register(
            "test2",
            user1,
            registry,
            address(0),
            roleBitmap,
            uint64(block.timestamp) + 86400
        );

        // Verify roles before burning
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_SUBREGISTRY,
                user1
            )
        );
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_RESOLVER,
                user1
            )
        );

        vm.prank(user1);
        registry.burn(tokenId);

        // Verify roles are revoked after burning
        assertFalse(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_SUBREGISTRY,
                user1
            )
        );
        assertFalse(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_RESOLVER,
                user1
            )
        );
    }

    function test_burn_emits_event() public {
        uint256 roleBitmap = DEFAULT_ROLE_BITMAP | RegistryRolesLib.ROLE_BURN;
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
        assertEq(entries[5].topics[0], keccak256("NameBurned(uint256,address)"));
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
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_BURN,
                address(2)
            )
        );
        vm.prank(address(2));
        registry.burn(tokenId);

        vm.assertEq(registry.ownerOf(tokenId), address(1));
        vm.assertEq(address(registry.getSubregistry("test2")), address(registry));
    }

    function test_expired_name_has_no_owner() public {
        address user = makeAddr("user");
        uint256 tokenId = registry.register(
            "test2",
            user,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );
        vm.warp(block.timestamp + 101);
        assertEq(registry.ownerOf(tokenId), address(0), "owner");
        assertEq(registry.latestOwnerOf(tokenId), user, "latest");
    }

    function test_expired_name_can_be_reregistered() public {
        string memory label = "test2";
        address user = makeAddr("user");
        uint256 tokenId = registry.register(
            label,
            user,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );
        assertEq(registry.ownerOf(tokenId), user, "owner0");
        vm.warp(block.timestamp + 101);
        assertEq(registry.ownerOf(tokenId), address(0), "owner1");
        assertEq(registry.latestOwnerOf(tokenId), user, "latest");
        address newUser = makeAddr("newUser");
        uint256 newTokenId = registry.register(
            label,
            newUser,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );
        assertEq(registry.ownerOf(newTokenId), newUser, "owner2");

        // The new token ID should be different from the old one
        assertNotEq(tokenId, newTokenId, "New token ID should be different");

        // Both should have the same canonical ID but different token version
        uint256 originalCanonicalId = registry.testGetResourceFromTokenId(tokenId);
        uint256 newCanonicalId = registry.testGetResourceFromTokenId(newTokenId);
        assertEq(originalCanonicalId, newCanonicalId, "Canonical IDs should be the same");

        uint32 originalTokenVersionId = registry.testGetTokenVersionId(tokenId);
        uint32 newTokenVersionId = registry.testGetTokenVersionId(newTokenId);
        assertEq(newTokenVersionId, originalTokenVersionId + 1, "Token version should increment");
    }

    function test_expired_name_returns_zero_subregistry() public {
        registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
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
            DEFAULT_ROLE_BITMAP,
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
            DEFAULT_ROLE_BITMAP,
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
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );

        // Create a user who is not the owner and has no roles
        address randomUser = address(2);
        assertFalse(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER,
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
                RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER,
                randomUser
            )
        );
        registry.setTokenObserver(tokenId, observer);
        vm.stopPrank();
    }

    function test_token_owner_without_role_cannot_set_observer() public {
        // Register a token with NO token observer role
        uint256 roleBitmap = RegistryRolesLib.ROLE_SET_SUBREGISTRY |
            RegistryRolesLib.ROLE_SET_RESOLVER; // Explicitly exclude RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER
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
                RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER,
                user1
            )
        );

        // Owner should not be able to set token observer without the role
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER,
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
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        address tokenObserverSetter = makeAddr("tokenObserverSetter");

        // Grant the SET_TOKEN_OBSERVER role specifically for this token to a non-owner
        registry.grantRoles(
            registry.testGetResourceFromTokenId(tokenId),
            RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER,
            tokenObserverSetter
        );

        // Verify the role was granted
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER,
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
        assertEq(address(registry.tokenObservers(newTokenId)), address(observer));
    }

    function test_Revert_renew_when_token_observer_reverts() public {
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
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
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );

        vm.recordLogs();
        registry.setTokenObserver(tokenId, observer);

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
        uint256 tokenId = registry.register(
            "resettest",
            owner1,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );

        // Grant an additional role to owner1
        registry.grantRoles(
            registry.testGetResourceFromTokenId(tokenId),
            RegistryRolesLib.ROLE_RENEW,
            owner1
        );

        // Verify owner1 has roles
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_SUBREGISTRY,
                owner1
            )
        );
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_RESOLVER,
                owner1
            )
        );
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER,
                owner1
            )
        );
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_RENEW,
                owner1
            )
        );

        uint256 originalResourceId = registry.testGetResourceFromTokenId(tokenId);
        uint32 originalEacVersionId = registry.testGetEacVersionIdFromEntry(tokenId);

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
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );

        // Verify it's a different token ID
        assertNotEq(newTokenId, tokenId, "Token ID should change after re-registration");

        // Verify eacVersionId has incremented
        uint32 newEacVersionId = registry.testGetEacVersionIdFromEntry(newTokenId);
        assertEq(
            newEacVersionId,
            originalEacVersionId + 1,
            "eacVersionId should increment on re-registration"
        );

        // Verify resource ID has changed due to eacVersionId increment
        uint256 newResourceId = registry.testGetResourceFromTokenId(newTokenId);
        assertNotEq(
            newResourceId,
            originalResourceId,
            "Resource ID should change after re-registration due to eacVersionId increment"
        );

        // owner1 should no longer have roles for this token
        // Test specifically using new resource ID
        assertFalse(
            registry.hasRoles(newResourceId, RegistryRolesLib.ROLE_SET_SUBREGISTRY, owner1)
        );
        assertFalse(registry.hasRoles(newResourceId, RegistryRolesLib.ROLE_SET_RESOLVER, owner1));
        assertFalse(
            registry.hasRoles(newResourceId, RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER, owner1)
        );
        assertFalse(registry.hasRoles(newResourceId, RegistryRolesLib.ROLE_RENEW, owner1));

        // And owner2 should have the default roles
        assertTrue(registry.hasRoles(newResourceId, RegistryRolesLib.ROLE_SET_SUBREGISTRY, owner2));
        assertTrue(registry.hasRoles(newResourceId, RegistryRolesLib.ROLE_SET_RESOLVER, owner2));
        assertTrue(
            registry.hasRoles(newResourceId, RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER, owner2)
        );
    }

    function test_eacVersionId_increments_on_reregistration_after_expiry() public {
        string memory label = "eactest";
        address owner1 = makeAddr("owner1");

        // Register a name initially
        uint256 tokenId = registry.register(
            label,
            owner1,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );

        // Get initial eacVersionId
        uint32 initialEacVersionId = registry.testGetEacVersionIdFromEntry(tokenId);
        uint256 initialResourceId = registry.testGetResourceFromTokenId(tokenId);

        // Let the name expire
        vm.warp(block.timestamp + 101);
        assertEq(registry.ownerOf(tokenId), address(0), "Token should be expired");

        // Re-register the same name with a different owner
        address owner2 = makeAddr("owner2");
        uint256 newTokenId = registry.register(
            label,
            owner2,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );

        // Verify eacVersionId has incremented
        uint32 newEacVersionId = registry.testGetEacVersionIdFromEntry(newTokenId);
        assertEq(
            newEacVersionId,
            initialEacVersionId + 1,
            "eacVersionId should increment on re-registration"
        );

        // Verify resource ID reflects the new eacVersionId
        uint256 newResourceId = registry.testGetResourceFromTokenId(newTokenId);
        assertNotEq(
            newResourceId,
            initialResourceId,
            "Resource ID should change due to eacVersionId increment"
        );

        // Verify the lower 32 bits of resource ID contain the new eacVersionId
        uint32 extractedEacVersionId = registry.testGetEacVersionId(newResourceId);
        assertEq(
            extractedEacVersionId,
            newEacVersionId,
            "Resource ID should contain the new eacVersionId in lower 32 bits"
        );
    }

    function test_register_send_to_null_expire_reregister_fresh_acl() public {
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        // Register a name initially with transfer admin role
        uint256 roleBitmapWithTransfer = DEFAULT_ROLE_BITMAP |
            RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN;
        uint256 tokenId = registry.register(
            "nulltest",
            user1,
            registry,
            address(0),
            roleBitmapWithTransfer,
            uint64(block.timestamp) + 100
        );

        // Grant additional roles
        uint256 resourceId = registry.testGetResourceFromTokenId(tokenId);
        registry.grantRoles(resourceId, RegistryRolesLib.ROLE_RENEW, user1);
        registry.grantRoles(resourceId, RegistryRolesLib.ROLE_SET_RESOLVER, user2);

        // Get current tokenId and eacVersionId after role grants
        uint256 currentTokenId = registry.testGetTokenIdFromResource(resourceId);
        uint32 initialEacVersionId = registry.testGetEacVersionIdFromEntry(currentTokenId);

        // Verify roles are set
        assertTrue(registry.hasRoles(resourceId, RegistryRolesLib.ROLE_RENEW, user1));
        assertTrue(registry.hasRoles(resourceId, RegistryRolesLib.ROLE_SET_RESOLVER, user2));

        // Transfer to temp address and let expire
        address tempOwner = makeAddr("temp");
        vm.prank(user1);
        registry.safeTransferFrom(user1, tempOwner, currentTokenId, 1, "");

        vm.warp(block.timestamp + 101);
        assertEq(registry.ownerOf(currentTokenId), address(0));

        // Re-register with new owner
        uint256 newTokenId = registry.register(
            "nulltest",
            user3,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );

        // Verify fresh ACL
        uint32 newEacVersionId = registry.testGetEacVersionIdFromEntry(newTokenId);
        assertEq(newEacVersionId, initialEacVersionId + 1);

        uint256 newResourceId = registry.testGetResourceFromTokenId(newTokenId);
        assertNotEq(newResourceId, resourceId);

        // Old users should have no roles
        assertFalse(registry.hasRoles(newResourceId, RegistryRolesLib.ROLE_RENEW, user1));
        assertFalse(registry.hasRoles(newResourceId, RegistryRolesLib.ROLE_SET_RESOLVER, user2));

        // New owner should have default roles
        assertTrue(registry.hasRoles(newResourceId, RegistryRolesLib.ROLE_SET_SUBREGISTRY, user3));
        assertTrue(registry.hasRoles(newResourceId, RegistryRolesLib.ROLE_SET_RESOLVER, user3));
    }

    function test_first_time_registration_no_eacVersionId_increment() public {
        string memory label = "firsttime";
        address owner = makeAddr("owner");

        // Verify name has never been registered (entry.expiry should be 0)
        (uint256 tokenId, IRegistryDatastore.Entry memory entry) = registry.getNameData(label);
        assertEq(entry.expiry, 0, "Name should never have been registered before");
        assertEq(entry.eacVersionId, 0, "Initial eacVersionId should be 0");

        // Register the name for the first time
        uint256 newTokenId = registry.register(
            label,
            owner,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );

        // Verify eacVersionId has NOT incremented (should still be 0)
        uint32 finalEacVersionId = registry.testGetEacVersionIdFromEntry(newTokenId);
        assertEq(finalEacVersionId, 0, "eacVersionId should remain 0 for first-time registration");

        // Verify the name is properly registered
        assertEq(registry.ownerOf(newTokenId), owner, "Owner should be set correctly");

        // Verify resource ID contains eacVersionId of 0
        uint256 resourceId = registry.testGetResourceFromTokenId(newTokenId);
        uint32 extractedEacVersionId = registry.testGetEacVersionId(resourceId);
        assertEq(
            extractedEacVersionId,
            0,
            "Resource ID should contain eacVersionId of 0 for first registration"
        );
    }

    function test_reregistration_with_existing_owner_increments_eacVersionId() public {
        string memory label = "existingowner";
        address owner1 = makeAddr("owner1");

        // Register a name initially
        uint256 tokenId = registry.register(
            label,
            owner1,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );

        // Get initial state
        uint32 initialEacVersionId = registry.testGetEacVersionIdFromEntry(tokenId);
        uint256 initialResourceId = registry.testGetResourceFromTokenId(tokenId);

        // Verify owner1 has the token
        assertEq(registry.ownerOf(tokenId), owner1, "owner1 should own the token");
        assertEq(registry.latestOwnerOf(tokenId), owner1, "owner1 should be latest owner");

        // Let the name expire but don't transfer/burn the token
        // This simulates the edge case where latestOwnerOf still returns an address
        vm.warp(block.timestamp + 101);

        // Verify token is expired but latestOwnerOf still returns owner1
        assertEq(
            registry.ownerOf(tokenId),
            address(0),
            "Token should be expired (ownerOf returns 0)"
        );
        assertEq(registry.latestOwnerOf(tokenId), owner1, "Latest owner should still be owner1");

        // Re-register the name with a new owner
        address owner2 = makeAddr("owner2");
        uint256 newTokenId = registry.register(
            label,
            owner2,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );

        // Verify the old token was burned and eacVersionId incremented
        uint32 newEacVersionId = registry.testGetEacVersionIdFromEntry(newTokenId);
        assertEq(
            newEacVersionId,
            initialEacVersionId + 1,
            "eacVersionId should increment even when previous owner existed"
        );

        // Verify resource ID changed
        uint256 newResourceId = registry.testGetResourceFromTokenId(newTokenId);
        assertNotEq(
            newResourceId,
            initialResourceId,
            "Resource ID should change due to eacVersionId increment"
        );

        // Verify new owner has the token
        assertEq(registry.ownerOf(newTokenId), owner2, "owner2 should own the new token");
        assertEq(
            registry.latestOwnerOf(newTokenId),
            owner2,
            "owner2 should be latest owner of new token"
        );

        // Verify token IDs are different
        assertNotEq(newTokenId, tokenId, "New token ID should be different from old token ID");

        // Verify old token is completely gone (should revert or return 0)
        assertEq(registry.ownerOf(tokenId), address(0), "Old token should have no owner");
    }

    function test_token_transfer_also_transfers_roles() public {
        // Register a name with owner1, including ROLE_CAN_TRANSFER_ADMIN
        address owner1 = makeAddr("owner1");
        uint256 roleBitmapWithTransfer = DEFAULT_ROLE_BITMAP |
            RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN;
        uint256 tokenId = registry.register(
            "transfertest",
            owner1,
            registry,
            address(0),
            roleBitmapWithTransfer,
            uint64(block.timestamp) + 100
        );

        // Capture the resource ID before transfer
        uint256 originalResourceId = registry.testGetResourceFromTokenId(tokenId);

        // Grant additional role to owner1
        registry.grantRoles(originalResourceId, RegistryRolesLib.ROLE_RENEW, owner1);

        // get the new token id
        uint256 newTokenId = registry.testGetTokenIdFromResource(originalResourceId);

        // Verify owner1 has roles
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(newTokenId),
                RegistryRolesLib.ROLE_SET_SUBREGISTRY,
                owner1
            )
        );
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(newTokenId),
                RegistryRolesLib.ROLE_SET_RESOLVER,
                owner1
            )
        );
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(newTokenId),
                RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER,
                owner1
            )
        );
        assertTrue(
            registry.hasRoles(
                registry.testGetResourceFromTokenId(newTokenId),
                RegistryRolesLib.ROLE_RENEW,
                owner1
            )
        );

        // Transfer to owner2
        address owner2 = makeAddr("owner2");
        vm.prank(owner1);
        registry.safeTransferFrom(owner1, owner2, newTokenId, 1, "");

        // Verify token ownership transferred
        assertEq(registry.ownerOf(newTokenId), owner2);

        // Verify the resource ID remains unchanged
        uint256 newResourceId = registry.testGetResourceFromTokenId(newTokenId);
        assertEq(newResourceId, originalResourceId, "Resource ID should be the same");

        // Check using the new resource ID that owner1 no longer has roles
        assertFalse(
            registry.hasRoles(newResourceId, RegistryRolesLib.ROLE_SET_SUBREGISTRY, owner1)
        );
        assertFalse(registry.hasRoles(newResourceId, RegistryRolesLib.ROLE_SET_RESOLVER, owner1));
        assertFalse(
            registry.hasRoles(newResourceId, RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER, owner1)
        );
        assertFalse(registry.hasRoles(newResourceId, RegistryRolesLib.ROLE_RENEW, owner1));

        // New owner should automatically receive any roles after transfer
        assertTrue(registry.hasRoles(newResourceId, RegistryRolesLib.ROLE_SET_SUBREGISTRY, owner2));
        assertTrue(registry.hasRoles(newResourceId, RegistryRolesLib.ROLE_SET_RESOLVER, owner2));
        assertTrue(
            registry.hasRoles(newResourceId, RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER, owner2)
        );
        assertTrue(registry.hasRoles(newResourceId, RegistryRolesLib.ROLE_RENEW, owner2));
    }

    function test_Revert_setTokenObserver_when_token_expired() public {
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );

        vm.warp(block.timestamp + 101);

        vm.expectRevert(abi.encodeWithSelector(IStandardRegistry.NameExpired.selector, tokenId));
        registry.setTokenObserver(tokenId, observer);
    }

    function test_Revert_setSubregistry_when_token_expired() public {
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );

        vm.warp(block.timestamp + 101);

        vm.expectRevert(abi.encodeWithSelector(IStandardRegistry.NameExpired.selector, tokenId));
        registry.setSubregistry(tokenId, IRegistry(address(this)));
    }

    function test_Revert_setResolver_when_token_expired() public {
        uint256 tokenId = registry.register(
            "test2",
            address(this),
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );

        vm.warp(block.timestamp + 101);

        vm.expectRevert(abi.encodeWithSelector(IStandardRegistry.NameExpired.selector, tokenId));
        registry.setResolver(tokenId, address(this));
    }

    function test_Revert_setTokenObserver_without_role_when_expired() public {
        uint256 tokenId = registry.register(
            "test2",
            user1,
            registry,
            address(0),
            NO_ROLES_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );

        vm.warp(block.timestamp + 101);

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER,
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
            NO_ROLES_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );

        vm.warp(block.timestamp + 101);

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_SUBREGISTRY,
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
            NO_ROLES_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );

        vm.warp(block.timestamp + 101);

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_RESOLVER,
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
            RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER,
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
            RegistryRolesLib.ROLE_SET_SUBREGISTRY,
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
            RegistryRolesLib.ROLE_SET_RESOLVER,
            uint64(block.timestamp) + 100
        );

        vm.prank(user1);
        registry.setResolver(tokenId, address(this));

        assertEq(registry.getResolver("test2"), address(this));
    }

    function test_Revert_setTokenObserver_without_role_when_not_expired() public {
        uint256 tokenId = registry.register(
            "test2",
            user1,
            registry,
            address(0),
            NO_ROLES_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER,
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
            NO_ROLES_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_SUBREGISTRY,
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
            NO_ROLES_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registry.testGetResourceFromTokenId(tokenId),
                RegistryRolesLib.ROLE_SET_RESOLVER,
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
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );

        // Record the resource ID (should remain stable)
        uint256 resourceId = registry.testGetResourceFromTokenId(tokenId);

        // Grant a new role to another user
        address user2 = makeAddr("user2");

        vm.recordLogs();
        registry.grantRoles(resourceId, RegistryRolesLib.ROLE_RENEW, user2);

        // Check for the TokenRegenerated event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundEvent = false;
        uint256 newTokenId;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("TokenRegenerated(uint256,uint256)")) {
                foundEvent = true;
                uint256 oldTokenIdFromEvent;
                (oldTokenIdFromEvent, newTokenId) = abi.decode(entries[i].data, (uint256, uint256));
                assertEq(oldTokenIdFromEvent, tokenId, "Old token ID in event doesn't match");
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
        assertTrue(registry.hasRoles(resourceId, RegistryRolesLib.ROLE_SET_SUBREGISTRY, owner1));
        assertTrue(registry.hasRoles(resourceId, RegistryRolesLib.ROLE_SET_RESOLVER, owner1));
        assertTrue(registry.hasRoles(resourceId, RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER, owner1));

        // Verify the granted role exists on the resource
        assertTrue(registry.hasRoles(resourceId, RegistryRolesLib.ROLE_RENEW, user2));
    }

    function test_token_regeneration_on_role_revoke() public {
        // Register a token with owner1
        address owner1 = makeAddr("owner1");
        uint256 tokenId = registry.register(
            "regenerate2",
            owner1,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );

        // Record the resource ID (should remain stable)
        uint256 resourceId = registry.testGetResourceFromTokenId(tokenId);

        // Grant a role to another user first
        address user2 = makeAddr("user2");
        registry.grantRoles(resourceId, RegistryRolesLib.ROLE_RENEW, user2);

        // Get the new token ID after first regeneration
        uint256 intermediateTokenId = registry.testGetTokenIdFromResource(resourceId);

        // revoke the role and check regeneration again
        vm.recordLogs();
        registry.revokeRoles(resourceId, RegistryRolesLib.ROLE_RENEW, user2);

        // Check for the TokenRegenerated event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundEvent = false;
        uint256 newTokenId;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("TokenRegenerated(uint256,uint256)")) {
                foundEvent = true;
                uint256 oldTokenIdFromEvent;
                (oldTokenIdFromEvent, newTokenId) = abi.decode(entries[i].data, (uint256, uint256));
                assertEq(
                    oldTokenIdFromEvent,
                    intermediateTokenId,
                    "Old token ID in event doesn't match"
                );
                break;
            }
        }

        assertTrue(foundEvent, "TokenRegenerated event not emitted");
        assertNotEq(newTokenId, intermediateTokenId, "Token ID should have changed");
        assertNotEq(newTokenId, tokenId, "Token ID should not revert to original");

        // Check that the new token ID has the same resource ID
        assertEq(
            registry.testGetResourceFromTokenId(newTokenId),
            resourceId,
            "Resource ID should remain the same"
        );

        // Verify the owner still owns the token (new token ID)
        assertEq(registry.ownerOf(newTokenId), owner1);

        // Verify the owner still has the same permissions
        assertTrue(registry.hasRoles(resourceId, RegistryRolesLib.ROLE_SET_SUBREGISTRY, owner1));
        assertTrue(registry.hasRoles(resourceId, RegistryRolesLib.ROLE_SET_RESOLVER, owner1));
        assertTrue(registry.hasRoles(resourceId, RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER, owner1));

        // Verify the revoked role is gone
        assertFalse(registry.hasRoles(resourceId, RegistryRolesLib.ROLE_RENEW, user2));
    }

    function test_maintaining_owner_roles_across_regenerations() public {
        // Register a token with owner1
        address owner1 = makeAddr("owner1");
        uint256 tokenId = registry.register(
            "regenerate3",
            owner1,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );

        // Record the resource ID (should remain stable)
        uint256 resourceId = registry.testGetResourceFromTokenId(tokenId);

        // Grant an additional role to the owner
        registry.grantRoles(resourceId, RegistryRolesLib.ROLE_RENEW, owner1);

        // Get the new token ID after regeneration
        uint256 intermediateTokenId = registry.testGetTokenIdFromResource(resourceId);

        // grant a role to another user, triggering another regeneration
        address user2 = makeAddr("user2");
        registry.grantRoles(resourceId, RegistryRolesLib.ROLE_RENEW, user2);

        // Get the final token ID
        uint256 finalTokenId = registry.testGetTokenIdFromResource(resourceId);

        // Verify the token has been regenerated twice
        assertNotEq(tokenId, intermediateTokenId, "Token should be regenerated first time");
        assertNotEq(intermediateTokenId, finalTokenId, "Token should be regenerated second time");

        // Verify the owner still owns the token (new token ID)
        assertEq(registry.ownerOf(finalTokenId), owner1, "still owns the token");

        // Verify the owner still has ALL the permissions
        assertTrue(registry.hasRoles(resourceId, RegistryRolesLib.ROLE_SET_SUBREGISTRY, owner1));
        assertTrue(registry.hasRoles(resourceId, RegistryRolesLib.ROLE_SET_RESOLVER, owner1));
        assertTrue(registry.hasRoles(resourceId, RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER, owner1));
        assertTrue(registry.hasRoles(resourceId, RegistryRolesLib.ROLE_RENEW, owner1));

        // Verify the other user has their role
        assertTrue(registry.hasRoles(resourceId, RegistryRolesLib.ROLE_RENEW, user2));
    }

    function test_token_regeneration_latestOwnerOf() public {
        address user = makeAddr("user");
        uint256 tokenId = registry.register(
            "regenerate4",
            user,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );
        uint256 resourceId = registry.testGetResourceFromTokenId(tokenId);
        registry.grantRoles(resourceId, RegistryRolesLib.ROLE_RENEW, user);
        uint256 newTokenId = registry.testGetTokenIdFromResource(resourceId);
        assertNotEq(tokenId, newTokenId, "token");
        vm.warp(block.timestamp + 101);
        assertEq(registry.ownerOf(tokenId), address(0), "owner0");
        assertEq(registry.latestOwnerOf(tokenId), address(0), "latest0");
        assertEq(registry.ownerOf(newTokenId), address(0), "owner1");
        assertEq(registry.latestOwnerOf(newTokenId), user, "latest1");
    }

    // getRoleAssigneeCount tests

    function test_getRoleAssigneeCount_single_role_single_assignee() public {
        uint256 tokenId = registry.register(
            "counttest1",
            user1,
            registry,
            address(0),
            RegistryRolesLib.ROLE_SET_RESOLVER,
            uint64(block.timestamp) + 86400
        );

        (uint256 counts, ) = registry.getAssigneeCount(tokenId, RegistryRolesLib.ROLE_SET_RESOLVER);

        // Count of 1 for ROLE_SET_RESOLVER
        uint256 expectedCount = 1 * RegistryRolesLib.ROLE_SET_RESOLVER;
        assertEq(counts, expectedCount, "Should have count of 1 for SET_RESOLVER role");
    }

    function test_getRoleAssigneeCount_single_role_multiple_assignees() public {
        uint256 tokenId = registry.register(
            "counttest2",
            user1,
            registry,
            address(0),
            RegistryRolesLib.ROLE_SET_RESOLVER,
            uint64(block.timestamp) + 86400
        );

        // Grant the same role to additional users
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        uint256 resourceId = registry.testGetResourceFromTokenId(tokenId);
        registry.grantRoles(resourceId, RegistryRolesLib.ROLE_SET_RESOLVER, user2);
        registry.grantRoles(resourceId, RegistryRolesLib.ROLE_SET_RESOLVER, user3);

        // Get the updated token ID after regenerations
        uint256 currentTokenId = registry.testGetTokenIdFromResource(resourceId);

        (uint256 counts, ) = registry.getAssigneeCount(
            currentTokenId,
            RegistryRolesLib.ROLE_SET_RESOLVER
        );

        // Should have count of 3 for ROLE_SET_RESOLVER
        uint256 expectedCount = 3 * RegistryRolesLib.ROLE_SET_RESOLVER;
        assertEq(counts, expectedCount, "Should have count of 3 for SET_RESOLVER role");
    }

    function test_getRoleAssigneeCount_single_role_no_assignees() public {
        uint256 tokenId = registry.register(
            "counttest3",
            user1,
            registry,
            address(0),
            RegistryRolesLib.ROLE_SET_RESOLVER,
            uint64(block.timestamp) + 86400
        );

        (uint256 counts, ) = registry.getAssigneeCount(tokenId, RegistryRolesLib.ROLE_RENEW);

        assertEq(counts, 0, "Should have count of 0 for unassigned RENEW role");
    }

    function test_getRoleAssigneeCount_multiple_roles_mixed_assignees() public {
        uint256 tokenId = registry.register(
            "counttest4",
            user1,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        // Grant additional roles to different users
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        uint256 resourceId = registry.testGetResourceFromTokenId(tokenId);
        registry.grantRoles(resourceId, RegistryRolesLib.ROLE_SET_RESOLVER, user2);
        registry.grantRoles(resourceId, RegistryRolesLib.ROLE_RENEW, user2);
        registry.grantRoles(resourceId, RegistryRolesLib.ROLE_RENEW, user3);

        // Get the updated token ID after regenerations
        uint256 currentTokenId = registry.testGetTokenIdFromResource(resourceId);

        // Query for SET_RESOLVER and RENEW roles
        uint256 queryBitmap = RegistryRolesLib.ROLE_SET_RESOLVER | RegistryRolesLib.ROLE_RENEW;
        (uint256 counts, ) = registry.getAssigneeCount(currentTokenId, queryBitmap);

        // user1 has SET_RESOLVER (from DEFAULT_ROLE_BITMAP), user2 has SET_RESOLVER + RENEW, user3 has RENEW
        // SET_RESOLVER: 2 assignees
        // RENEW: 2 assignees
        uint256 expectedCount = (2 * RegistryRolesLib.ROLE_SET_RESOLVER) |
            (2 * RegistryRolesLib.ROLE_RENEW);
        assertEq(counts, expectedCount, "Should have correct counts for both roles");
    }

    function test_getRoleAssigneeCount_multiple_roles_partial_assignees() public {
        uint256 tokenId = registry.register(
            "counttest5",
            user1,
            registry,
            address(0),
            RegistryRolesLib.ROLE_SET_RESOLVER,
            uint64(block.timestamp) + 86400
        );

        // Query for multiple roles where only SET_RESOLVER has assignees
        uint256 queryBitmap = RegistryRolesLib.ROLE_SET_RESOLVER |
            RegistryRolesLib.ROLE_RENEW |
            RegistryRolesLib.ROLE_BURN;
        (uint256 counts, ) = registry.getAssigneeCount(tokenId, queryBitmap);

        // Only SET_RESOLVER should have 1 assignee
        uint256 expectedCount = 1 * RegistryRolesLib.ROLE_SET_RESOLVER;
        assertEq(counts, expectedCount, "Should have count only for SET_RESOLVER");
    }

    function test_getRoleAssigneeCount_all_default_roles() public {
        uint256 tokenId = registry.register(
            "counttest6",
            user1,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        (uint256 counts, ) = registry.getAssigneeCount(tokenId, DEFAULT_ROLE_BITMAP);

        // DEFAULT_ROLE_BITMAP includes SET_SUBREGISTRY, SET_RESOLVER, SET_TOKEN_OBSERVER
        // Each should have 1 assignee
        uint256 expectedCount = (1 * RegistryRolesLib.ROLE_SET_SUBREGISTRY) |
            (1 * RegistryRolesLib.ROLE_SET_RESOLVER) |
            (1 * RegistryRolesLib.ROLE_SET_TOKEN_OBSERVER);
        assertEq(counts, expectedCount, "Should have count of 1 for each default role");
    }

    function test_getRoleAssigneeCount_overlapping_role_assignments() public {
        uint256 tokenId = registry.register(
            "counttest7",
            user1,
            registry,
            address(0),
            RegistryRolesLib.ROLE_SET_RESOLVER,
            uint64(block.timestamp) + 86400
        );

        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        uint256 resourceId = registry.testGetResourceFromTokenId(tokenId);

        // Grant overlapping roles
        registry.grantRoles(
            resourceId,
            RegistryRolesLib.ROLE_SET_RESOLVER | RegistryRolesLib.ROLE_RENEW,
            user2
        );
        registry.grantRoles(
            resourceId,
            RegistryRolesLib.ROLE_RENEW | RegistryRolesLib.ROLE_BURN,
            user3
        );

        // Get the updated token ID after regenerations
        uint256 currentTokenId = registry.testGetTokenIdFromResource(resourceId);

        // Query for all three roles
        uint256 queryBitmap = RegistryRolesLib.ROLE_SET_RESOLVER |
            RegistryRolesLib.ROLE_RENEW |
            RegistryRolesLib.ROLE_BURN;
        (uint256 counts, ) = registry.getAssigneeCount(currentTokenId, queryBitmap);

        // user1: SET_RESOLVER
        // user2: SET_RESOLVER, RENEW
        // user3: RENEW, BURN
        // SET_RESOLVER: 2 assignees -> 2 at bit position of ROLE_SET_RESOLVER
        // RENEW: 2 assignees -> 2 at bit position of ROLE_RENEW
        // BURN: 1 assignee -> 1 at bit position of ROLE_BURN
        uint256 expectedCount = (2 * RegistryRolesLib.ROLE_SET_RESOLVER) |
            (2 * RegistryRolesLib.ROLE_RENEW) |
            (1 * RegistryRolesLib.ROLE_BURN);
        assertEq(counts, expectedCount, "Should have correct counts for all roles");
    }

    function test_getRoleAssigneeCount_after_role_revocation() public {
        uint256 tokenId = registry.register(
            "counttest8",
            user1,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        address user2 = makeAddr("user2");
        uint256 resourceId = registry.testGetResourceFromTokenId(tokenId);

        // Grant role to user2
        registry.grantRoles(resourceId, RegistryRolesLib.ROLE_SET_RESOLVER, user2);
        uint256 tokenIdAfterGrant = registry.testGetTokenIdFromResource(resourceId);

        // Check count before revocation - should have 2 assignees for SET_RESOLVER
        (uint256 countsBefore, ) = registry.getAssigneeCount(
            tokenIdAfterGrant,
            RegistryRolesLib.ROLE_SET_RESOLVER
        );
        uint256 expectedCountBefore = 2 * RegistryRolesLib.ROLE_SET_RESOLVER;
        assertEq(countsBefore, expectedCountBefore, "Should have 2 assignees before revocation");

        // Revoke role from user2
        registry.revokeRoles(resourceId, RegistryRolesLib.ROLE_SET_RESOLVER, user2);
        uint256 tokenIdAfterRevoke = registry.testGetTokenIdFromResource(resourceId);

        // Check count after revocation - should have 1 assignee for SET_RESOLVER
        (uint256 countsAfter, ) = registry.getAssigneeCount(
            tokenIdAfterRevoke,
            RegistryRolesLib.ROLE_SET_RESOLVER
        );
        uint256 expectedCountAfter = 1 * RegistryRolesLib.ROLE_SET_RESOLVER;
        assertEq(countsAfter, expectedCountAfter, "Should have 1 assignee after revocation");
    }

    function test_getRoleAssigneeCount_zero_bitmap() public {
        uint256 tokenId = registry.register(
            "counttest9",
            user1,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        (uint256 counts, ) = registry.getAssigneeCount(tokenId, 0);

        assertEq(counts, 0, "Should have 0 counts for empty bitmap");
    }

    function test_transfer_succeeds_with_max_assignees_BET_430() public {
        // Register a token with default roles including ROLE_CAN_TRANSFER_ADMIN
        address tokenOwner = makeAddr("tokenOwner");
        uint256 roleBitmapWithTransfer = DEFAULT_ROLE_BITMAP |
            RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN;
        uint256 tokenId = registry.register(
            "maxtransfertest",
            tokenOwner,
            registry,
            address(0),
            roleBitmapWithTransfer,
            uint64(block.timestamp) + 86400
        );

        uint256 resourceId = registry.testGetResourceFromTokenId(tokenId);

        // Create 14 additional addresses and grant them the same role as the token owner has
        address[] memory additionalUsers = new address[](14);
        for (uint256 i = 0; i < 14; i++) {
            additionalUsers[i] = makeAddr(string(abi.encodePacked("maxUser", i)));
            // Grant ROLE_SET_RESOLVER to reach max assignees (owner + 14 others = 15 total)
            registry.grantRoles(resourceId, RegistryRolesLib.ROLE_SET_RESOLVER, additionalUsers[i]);
        }

        // Get the current token ID after role grants (which may have triggered regeneration)
        uint256 currentTokenId = registry.testGetTokenIdFromResource(resourceId);

        // Verify we have 15 assignees for ROLE_SET_RESOLVER (max allowed)
        (uint256 counts, ) = registry.getAssigneeCount(
            currentTokenId,
            RegistryRolesLib.ROLE_SET_RESOLVER
        );
        uint256 expectedCount = 15 * RegistryRolesLib.ROLE_SET_RESOLVER;
        assertEq(counts, expectedCount, "Should have 15 assignees for ROLE_SET_RESOLVER");

        // attempt to transfer the token to a new address
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
            registry.hasRoles(resourceId, RegistryRolesLib.ROLE_SET_RESOLVER, newOwner),
            "New owner should have ROLE_SET_RESOLVER"
        );

        // Verify the old owner no longer has roles
        assertFalse(
            registry.hasRoles(resourceId, RegistryRolesLib.ROLE_SET_RESOLVER, tokenOwner),
            "Old owner should no longer have ROLE_SET_RESOLVER"
        );

        // Verify we still have 15 total assignees (the 14 additional users + new owner)
        (uint256 countsAfter, ) = registry.getAssigneeCount(
            currentTokenId,
            RegistryRolesLib.ROLE_SET_RESOLVER
        );
        assertEq(countsAfter, expectedCount, "Should still have 15 assignees after transfer");
    }

    function test_getRoleAssigneeCount_nonexistent_role() public {
        uint256 tokenId = registry.register(
            "counttest10",
            user1,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        // Use a role that doesn't exist in the registry roles
        uint256 nonexistentRole = RegistryRolesLib.ROLE_BURN; // Use BURN role which won't be assigned during default registration
        (uint256 counts, ) = registry.getAssigneeCount(tokenId, nonexistentRole);

        assertEq(counts, 0, "Should have 0 counts for nonexistent role");
    }

    // Token ID Generation Tests

    function test_constructTokenId_basic() public view {
        uint256 canonicalId = 0x123456789ABCDEF000000000000000000000000000000000;
        uint32 tokenVersionId = 42;

        uint256 tokenId = registry.testConstructTokenId(canonicalId, tokenVersionId);

        // Verify the token ID contains the correct components
        uint256 extractedCanonicalId = LibLabel.getCanonicalId(tokenId);
        uint32 extractedTokenVersionId = registry.testGetTokenVersionId(tokenId);

        assertEq(extractedCanonicalId, canonicalId, "Canonical ID should be preserved");
        assertEq(extractedTokenVersionId, tokenVersionId, "Token version ID should be preserved");
    }

    function test_constructTokenId_with_max_values() public view {
        uint256 canonicalId = uint256(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) << 32; // Upper bits set
        uint32 tokenVersionId = type(uint32).max;

        uint256 tokenId = registry.testConstructTokenId(canonicalId, tokenVersionId);

        // Verify all components are preserved even at max values
        uint256 extractedCanonicalId = LibLabel.getCanonicalId(tokenId);
        uint32 extractedTokenVersionId = registry.testGetTokenVersionId(tokenId);

        assertEq(extractedCanonicalId, canonicalId, "Max canonical ID should be preserved");
        assertEq(
            extractedTokenVersionId,
            tokenVersionId,
            "Max token version ID should be preserved"
        );
    }

    function test_constructTokenId_with_zero_values() public view {
        uint256 canonicalId = 0x123456789ABCDEF000000000000000000000000000000000;
        uint32 tokenVersionId = 0;

        uint256 tokenId = registry.testConstructTokenId(canonicalId, tokenVersionId);

        // Verify zero values are handled correctly
        uint256 extractedCanonicalId = LibLabel.getCanonicalId(tokenId);
        uint32 extractedTokenVersionId = registry.testGetTokenVersionId(tokenId);

        assertEq(
            extractedCanonicalId,
            canonicalId,
            "Canonical ID should be preserved with zero versions"
        );
        assertEq(extractedTokenVersionId, 0, "Zero token version ID should be preserved");
    }

    function test_tokenId_bit_layout() public view {
        uint256 canonicalId = 0x123456789ABCDEF000000000000000000000000000000000;
        uint32 tokenVersionId = 0x12345678;

        uint256 tokenId = registry.testConstructTokenId(canonicalId, tokenVersionId);

        // Verify bit layout manually
        // Lower 32 bits should be tokenVersionId
        uint256 lowerBits = tokenId & 0xFFFFFFFF;
        assertEq(lowerBits, uint256(tokenVersionId), "Lower 32 bits should be token version ID");

        // Upper bits should match canonical ID (everything except lower 32 bits)
        uint256 upperBits = tokenId & ~uint256(0xFFFFFFFF);
        assertEq(upperBits, canonicalId, "Upper bits should match canonical ID");
    }

    function test_registration_generates_correct_tokenId() public {
        string memory label = "tokentest";
        uint256 tokenId = registry.register(
            label,
            user1,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        // Verify the token ID has correct structure
        uint256 canonicalId = LibLabel.getCanonicalId(tokenId);
        uint32 tokenVersionId = registry.testGetTokenVersionId(tokenId);

        // First registration should have version ID of 0
        assertEq(tokenVersionId, 0, "Initial token version ID should be 0");

        // Canonical ID should match label hash with lower 32 bits cleared
        uint256 expectedCanonicalId = LibLabel.labelToCanonicalId(label);
        assertEq(canonicalId, expectedCanonicalId, "Canonical ID should match label hash");
    }

    function test_token_regeneration_increments_tokenVersionId() public {
        string memory label = "regentest";
        uint256 tokenId = registry.register(
            label,
            user1,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        uint256 resourceId = registry.testGetResourceFromTokenId(tokenId);
        uint32 initialTokenVersionId = registry.testGetTokenVersionId(tokenId);

        // Grant a role to trigger regeneration
        address user2 = makeAddr("user2");
        registry.grantRoles(resourceId, RegistryRolesLib.ROLE_RENEW, user2);

        // Get the new token ID
        uint256 newTokenId = registry.testGetTokenIdFromResource(resourceId);
        uint32 newTokenVersionId = registry.testGetTokenVersionId(newTokenId);

        // Token version should increment
        assertEq(newTokenVersionId, initialTokenVersionId + 1, "Token version ID should increment");

        // Resource ID should remain the same (EAC version is stable within the resource)
        uint256 newResourceId = registry.testGetResourceFromTokenId(newTokenId);
        assertEq(newResourceId, resourceId, "Resource ID should remain the same");
    }

    function test_multiple_regenerations_increment_correctly() public {
        string memory label = "multiregentest";
        uint256 tokenId = registry.register(
            label,
            user1,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        uint256 resourceId = registry.testGetResourceFromTokenId(tokenId);
        uint32 initialTokenVersionId = registry.testGetTokenVersionId(tokenId);

        // Perform multiple role operations to trigger multiple regenerations
        address user2 = makeAddr("multiUser2");
        address user3 = makeAddr("multiUser3");

        // First regeneration
        registry.grantRoles(resourceId, RegistryRolesLib.ROLE_RENEW, user2);
        uint256 tokenId1 = registry.testGetTokenIdFromResource(resourceId);
        uint32 tokenVersionId1 = registry.testGetTokenVersionId(tokenId1);

        // Second regeneration
        registry.grantRoles(resourceId, RegistryRolesLib.ROLE_BURN, user3);
        uint256 tokenId2 = registry.testGetTokenIdFromResource(resourceId);
        uint32 tokenVersionId2 = registry.testGetTokenVersionId(tokenId2);

        // Third regeneration
        registry.revokeRoles(resourceId, RegistryRolesLib.ROLE_RENEW, user2);
        uint256 tokenId3 = registry.testGetTokenIdFromResource(resourceId);
        uint32 tokenVersionId3 = registry.testGetTokenVersionId(tokenId3);

        // Verify incremental progression
        assertEq(
            tokenVersionId1,
            initialTokenVersionId + 1,
            "First regeneration should increment by 1"
        );
        assertEq(
            tokenVersionId2,
            initialTokenVersionId + 2,
            "Second regeneration should increment by 2"
        );
        assertEq(
            tokenVersionId3,
            initialTokenVersionId + 3,
            "Third regeneration should increment by 3"
        );
    }

    function test_reregistration_after_expiry_resets_tokenVersionId() public {
        string memory label = "expirytest";
        uint256 tokenId = registry.register(
            label,
            user1,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );

        uint256 resourceId = registry.testGetResourceFromTokenId(tokenId);

        // Trigger some regenerations to increment version
        address user2 = makeAddr("expiryUser2");
        registry.grantRoles(resourceId, RegistryRolesLib.ROLE_RENEW, user2);
        registry.grantRoles(resourceId, RegistryRolesLib.ROLE_BURN, user2);

        uint256 preExpiryTokenId = registry.testGetTokenIdFromResource(resourceId);
        uint32 preExpiryTokenVersionId = registry.testGetTokenVersionId(preExpiryTokenId);

        // Should have incremented
        assertGt(preExpiryTokenVersionId, 0, "Pre-expiry token version should have incremented");

        // Expire the token
        vm.warp(block.timestamp + 101);

        // Re-register
        address newOwner = makeAddr("newExpiryOwner");
        uint256 newTokenId = registry.register(
            label,
            newOwner,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );

        uint32 newTokenVersionId = registry.testGetTokenVersionId(newTokenId);

        // Token version should increment even after expiry
        assertEq(
            newTokenVersionId,
            preExpiryTokenVersionId + 1,
            "New registration should increment token version ID"
        );

        // But the new token ID should be different from the expired one
        assertNotEq(
            newTokenId,
            preExpiryTokenId,
            "New token ID should be different after re-registration"
        );
    }

    // Integration and Edge Case Tests

    function test_tokenId_consistency_across_operations() public {
        string memory label = "consistencytest";
        uint256 tokenId = registry.register(
            label,
            user1,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        uint256 resourceId = registry.testGetResourceFromTokenId(tokenId);

        // Store initial state
        uint32 initialTokenVersionId = registry.testGetTokenVersionId(tokenId);

        // Perform various operations that should maintain consistency
        registry.setSubregistry(tokenId, IRegistry(address(this)));
        registry.setResolver(tokenId, address(this));
        registry.renew(tokenId, uint64(block.timestamp) + 172800);

        // Token ID should remain the same for non-regenerating operations
        assertEq(registry.ownerOf(tokenId), user1, "Owner should remain the same");
        assertEq(
            registry.testGetTokenVersionId(tokenId),
            initialTokenVersionId,
            "Token version should not change"
        );

        // Resource ID should remain consistent
        uint256 currentResourceId = registry.testGetResourceFromTokenId(tokenId);
        assertEq(currentResourceId, resourceId, "Resource ID should remain consistent");
    }

    function test_tokenId_transfer_maintains_structure() public {
        string memory label = "transferstructure";
        uint256 roleBitmapWithTransfer = DEFAULT_ROLE_BITMAP |
            RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN;
        uint256 tokenId = registry.register(
            label,
            user1,
            registry,
            address(0),
            roleBitmapWithTransfer,
            uint64(block.timestamp) + 86400
        );

        // Trigger regeneration to get non-zero version
        uint256 resourceId = registry.testGetResourceFromTokenId(tokenId);
        address user2 = makeAddr("transferUser2");
        registry.grantRoles(resourceId, RegistryRolesLib.ROLE_RENEW, user2);

        uint256 regeneratedTokenId = registry.testGetTokenIdFromResource(resourceId);
        uint32 preTransferTokenVersionId = registry.testGetTokenVersionId(regeneratedTokenId);

        // Transfer the token
        address user3 = makeAddr("transferUser3");
        vm.prank(user1);
        registry.safeTransferFrom(user1, user3, regeneratedTokenId, 1, "");

        // Verify token ID structure is preserved after transfer
        assertEq(registry.ownerOf(regeneratedTokenId), user3, "Token should be transferred");
        assertEq(
            registry.testGetTokenVersionId(regeneratedTokenId),
            preTransferTokenVersionId,
            "Token version should be preserved"
        );

        // Resource ID should remain the same
        uint256 postTransferResourceId = registry.testGetResourceFromTokenId(regeneratedTokenId);
        assertEq(
            postTransferResourceId,
            resourceId,
            "Resource ID should remain the same after transfer"
        );
    }

    function test_tokenId_edge_case_max_uint32_versions() public view {
        // This test verifies the system can handle maximum version values
        // We'll use the test helper to construct a token ID with max versions
        uint256 canonicalId = LibLabel.labelToCanonicalId("maxtest");
        uint32 maxTokenVersionId = type(uint32).max;

        uint256 tokenId = registry.testConstructTokenId(canonicalId, maxTokenVersionId);

        // Verify extraction works correctly even at max values
        assertEq(
            LibLabel.getCanonicalId(tokenId),
            canonicalId,
            "Canonical ID should be extracted correctly"
        );
        assertEq(
            registry.testGetTokenVersionId(tokenId),
            maxTokenVersionId,
            "Max token version should be extracted correctly"
        );

        // Verify no bit overlap or corruption
        uint256 reconstructed = registry.testConstructTokenId(
            canonicalId,
            registry.testGetTokenVersionId(tokenId)
        );
        assertEq(tokenId, reconstructed, "Reconstructed token ID should match original");
    }

    function test_tokenId_uniqueness_across_labels() public {
        // Register multiple tokens and ensure they have unique IDs
        string[] memory labels = new string[](5);
        labels[0] = "unique1";
        labels[1] = "unique2";
        labels[2] = "unique3";
        labels[3] = "unique4";
        labels[4] = "unique5";

        uint256[] memory tokenIds = new uint256[](5);
        uint256[] memory canonicalIds = new uint256[](5);

        for (uint256 i = 0; i < labels.length; i++) {
            tokenIds[i] = registry.register(
                labels[i],
                user1,
                registry,
                address(0),
                DEFAULT_ROLE_BITMAP,
                uint64(block.timestamp) + 86400
            );
            canonicalIds[i] = registry.testGetResourceFromTokenId(tokenIds[i]);
        }

        // Verify all token IDs are unique
        for (uint256 i = 0; i < tokenIds.length; i++) {
            for (uint256 j = i + 1; j < tokenIds.length; j++) {
                assertNotEq(tokenIds[i], tokenIds[j], "Token IDs should be unique");
                assertNotEq(canonicalIds[i], canonicalIds[j], "Canonical IDs should be unique");
            }
        }
    }

    function test_tokenId_different_versions() public view {
        // Test that changes to token version ID create different token IDs
        uint256 canonicalId = LibLabel.labelToCanonicalId("isolationtest");

        // Start with specific values
        uint32 tokenVersionId1 = 0x12345678;
        uint256 tokenId1 = registry.testConstructTokenId(canonicalId, tokenVersionId1);

        // Change token version ID
        uint32 tokenVersionId2 = 0x87654321;
        uint256 tokenId2 = registry.testConstructTokenId(canonicalId, tokenVersionId2);

        // Verify canonical ID is same, versions are different
        assertEq(LibLabel.getCanonicalId(tokenId1), canonicalId, "Canonical ID 1 should match");
        assertEq(LibLabel.getCanonicalId(tokenId2), canonicalId, "Canonical ID 2 should match");

        assertEq(
            registry.testGetTokenVersionId(tokenId1),
            tokenVersionId1,
            "Token version 1 should match"
        );
        assertEq(
            registry.testGetTokenVersionId(tokenId2),
            tokenVersionId2,
            "Token version 2 should be different"
        );

        // Token IDs should be different
        assertNotEq(tokenId1, tokenId2, "Token IDs should be different");
    }

    function test_tokenId_zero_canonical_id_edge_case() public view {
        // Test edge case where canonical ID might be zero (though unlikely in practice)
        uint256 zeroCanonicalId = 0;
        uint32 tokenVersionId = 42;

        uint256 tokenId = registry.testConstructTokenId(zeroCanonicalId, tokenVersionId);

        // Verify extraction works with zero canonical ID
        assertEq(
            LibLabel.getCanonicalId(tokenId),
            zeroCanonicalId,
            "Zero canonical ID should be preserved"
        );
        assertEq(
            registry.testGetTokenVersionId(tokenId),
            tokenVersionId,
            "Token version should be preserved"
        );

        // Token ID should just be the version ID
        uint256 expectedTokenId = uint256(tokenVersionId);
        assertEq(tokenId, expectedTokenId, "Token ID should match expected value");
    }

    function test_resource_token_roundtrip() public {
        string memory label = "roundtriptest";
        uint256 tokenId = registry.register(
            label,
            user1,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        uint256 resourceId = registry.testGetResourceFromTokenId(tokenId);
        uint256 reconstructedTokenId = registry.testGetTokenIdFromResource(resourceId);

        // The reconstructed token ID should equal the original
        assertEq(reconstructedTokenId, tokenId, "Round-trip conversion should work");

        // Check that the owner is correctly recognized
        address owner = registry.ownerOf(reconstructedTokenId);
        assertEq(owner, user1, "Owner should be found for reconstructed token ID");
    }

    function test_getNameData_returns_correct_tokenId() public {
        string memory label = "namedatatest";
        uint256 registeredTokenId = registry.register(
            label,
            user1,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        // Trigger regeneration
        uint256 resourceId = registry.testGetResourceFromTokenId(registeredTokenId);
        address user2 = makeAddr("namedataUser2");
        registry.grantRoles(resourceId, RegistryRolesLib.ROLE_RENEW, user2);

        // Get current token ID after regeneration
        uint256 currentTokenId = registry.testGetTokenIdFromResource(resourceId);

        // Use getNameData to retrieve token ID
        (uint256 retrievedTokenId, IRegistryDatastore.Entry memory entry) = registry.getNameData(
            label
        );

        // Should match the current (regenerated) token ID
        assertEq(retrievedTokenId, currentTokenId, "getNameData should return current token ID");
        assertNotEq(
            retrievedTokenId,
            registeredTokenId,
            "Should not return original token ID after regeneration"
        );

        // Verify entry data matches
        IRegistryDatastore.Entry memory currentEntry = registry.testGetEntry(currentTokenId);
        assertEq(
            entry.tokenVersionId,
            currentEntry.tokenVersionId,
            "Entry token version should match"
        );
        assertEq(entry.eacVersionId, currentEntry.eacVersionId, "Entry EAC version should match");
    }
    function testCanonicalIdOptimization() public {
        uint256 tokenId = registry.register(
            "optimization",
            user1,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 100
        );

        (IRegistryDatastore.Entry memory entry, uint256 canonicalId) = registry
            .testGetEntryWithCanonicalId(tokenId);

        uint256 resourceFromOptimized = registry.testGetResourceFromTokenId(tokenId);
        uint256 tokenFromOptimized = registry.testGetTokenIdFromResource(resourceFromOptimized);

        assertEq(tokenFromOptimized, tokenId, "Token ID should match after round-trip");
        assertEq(
            canonicalId,
            LibLabel.getCanonicalId(tokenId),
            "Canonical ID should match LibLabel calculation"
        );

        uint256 expectedResource = canonicalId | uint256(entry.eacVersionId);
        assertEq(
            resourceFromOptimized,
            expectedResource,
            "Resource ID should be correctly calculated"
        );
    }

    // ROLE_CAN_TRANSFER_ADMIN tests
    function test_transfer_with_role_can_transfer_admin() public {
        // Register a name with ROLE_CAN_TRANSFER_ADMIN included
        uint256 roleBitmapWithTransfer = DEFAULT_ROLE_BITMAP |
            RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN;
        uint256 tokenId = registry.register(
            "transfertest1",
            user1,
            registry,
            address(0),
            roleBitmapWithTransfer,
            uint64(block.timestamp) + 86400
        );

        address user2 = makeAddr("user2");

        // Transfer should succeed
        vm.prank(user1);
        registry.safeTransferFrom(user1, user2, tokenId, 1, "");

        assertEq(registry.ownerOf(tokenId), user2);
    }

    function test_Revert_transfer_without_role_can_transfer_admin() public {
        // Register a name without ROLE_CAN_TRANSFER_ADMIN
        uint256 tokenId = registry.register(
            "transfertest2",
            user1,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        address user2 = makeAddr("user2");

        // Transfer should revert
        vm.expectRevert(
            abi.encodeWithSelector(IStandardRegistry.TransferDisallowed.selector, tokenId, user1)
        );
        vm.prank(user1);
        registry.safeTransferFrom(user1, user2, tokenId, 1, "");
    }

    function test_transfer_after_revoking_role_can_transfer_admin() public {
        // Register a name with ROLE_CAN_TRANSFER_ADMIN
        uint256 roleBitmapWithTransfer = DEFAULT_ROLE_BITMAP |
            RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN;
        uint256 tokenId = registry.register(
            "transfertest4",
            user1,
            registry,
            address(0),
            roleBitmapWithTransfer,
            uint64(block.timestamp) + 86400
        );
        uint256 resource = registry.testGetResourceFromTokenId(tokenId);

        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        // First transfer should succeed
        vm.prank(user1);
        registry.safeTransferFrom(user1, user2, tokenId, 1, "");
        assertEq(registry.ownerOf(tokenId), user2);

        // Revoke ROLE_CAN_TRANSFER_ADMIN from user2
        registry.revokeRoles(resource, RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN, user2);
        uint256 newTokenId = registry.testGetTokenIdFromResource(resource);

        // Transfer should now fail
        vm.expectRevert(
            abi.encodeWithSelector(IStandardRegistry.TransferDisallowed.selector, newTokenId, user2)
        );
        vm.prank(user2);
        registry.safeTransferFrom(user2, user3, newTokenId, 1, "");
    }

    function test_batch_transfer_requires_role_can_transfer_admin() public {
        // Register two names, one with ROLE_CAN_TRANSFER_ADMIN, one without
        uint256 roleBitmapWithTransfer = DEFAULT_ROLE_BITMAP |
            RegistryRolesLib.ROLE_CAN_TRANSFER_ADMIN;
        uint256 tokenId1 = registry.register(
            "batchtest1",
            user1,
            registry,
            address(0),
            roleBitmapWithTransfer,
            uint64(block.timestamp) + 86400
        );
        uint256 tokenId2 = registry.register(
            "batchtest2",
            user1,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        address user2 = makeAddr("user2");

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;

        // Batch transfer should fail because tokenId2 lacks ROLE_CAN_TRANSFER_ADMIN
        vm.expectRevert(
            abi.encodeWithSelector(IStandardRegistry.TransferDisallowed.selector, tokenId2, user1)
        );
        vm.prank(user1);
        registry.safeBatchTransferFrom(user1, user2, tokenIds, amounts, "");
    }

    function test_burn_does_not_require_role_can_transfer_admin() public {
        // Register a name without ROLE_CAN_TRANSFER_ADMIN but with ROLE_BURN
        uint256 roleBitmapWithBurn = DEFAULT_ROLE_BITMAP | RegistryRolesLib.ROLE_BURN;
        uint256 tokenId = registry.register(
            "burntest",
            user1,
            registry,
            address(0),
            roleBitmapWithBurn,
            uint64(block.timestamp) + 86400
        );

        // Burn should succeed even without ROLE_CAN_TRANSFER_ADMIN
        vm.prank(user1);
        registry.burn(tokenId);

        assertEq(registry.ownerOf(tokenId), address(0));
    }

    function test_mint_does_not_require_role_can_transfer_admin() public {
        // This is tested implicitly by register() function calls above
        // Mints (from address(0)) should not require ROLE_CAN_TRANSFER_ADMIN
        uint256 tokenId = registry.register(
            "minttest",
            user1,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        assertEq(registry.ownerOf(tokenId), user1);
    }

    function test_token_regeneration_works_without_role_can_transfer_admin() public {
        // Register a name without ROLE_CAN_TRANSFER_ADMIN
        uint256 tokenId = registry.register(
            "regentest",
            user1,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );
        uint256 resource = registry.testGetResourceFromTokenId(tokenId);

        // Grant another role to trigger regeneration
        registry.grantRoles(resource, RegistryRolesLib.ROLE_RENEW, user1);

        // Token should regenerate successfully (internal burn + mint)
        uint256 newTokenId = registry.testGetTokenIdFromResource(resource);
        assertNotEq(tokenId, newTokenId);
        assertEq(registry.ownerOf(newTokenId), user1);
    }

    function test_approved_operator_cannot_transfer_without_role_can_transfer_admin() public {
        // Register a name without ROLE_CAN_TRANSFER_ADMIN
        uint256 tokenId = registry.register(
            "approvaltest",
            user1,
            registry,
            address(0),
            DEFAULT_ROLE_BITMAP,
            uint64(block.timestamp) + 86400
        );

        address operator = makeAddr("operator");
        address user2 = makeAddr("user2");

        // Approve operator
        vm.prank(user1);
        registry.setApprovalForAll(operator, true);

        // Operator should not be able to transfer without ROLE_CAN_TRANSFER_ADMIN on the owner
        vm.expectRevert(
            abi.encodeWithSelector(IStandardRegistry.TransferDisallowed.selector, tokenId, user1)
        );
        vm.prank(operator);
        registry.safeTransferFrom(user1, user2, tokenId, 1, "");
    }
}

contract MockTokenObserver is ITokenObserver {
    uint256 public lastTokenId;
    uint64 public lastExpiry;
    address public lastCaller;

    function onRenew(uint256 tokenId, uint64 expires, address renewedBy) external {
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
