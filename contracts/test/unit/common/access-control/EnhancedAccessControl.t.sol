// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering, one-contract-per-file

import {Test, Vm} from "forge-std/Test.sol";

import {EnhancedAccessControl} from "~src/common/access-control/EnhancedAccessControl.sol";
import {
    IEnhancedAccessControl
} from "~src/common/access-control/interfaces/IEnhancedAccessControl.sol";
import {EACBaseRolesLib} from "~src/common/access-control/libraries/EACBaseRolesLib.sol";

abstract contract MockRoles {
    uint256 public constant RESOURCE_1 = uint256(keccak256("RESOURCE_1"));
    uint256 public constant RESOURCE_2 = uint256(keccak256("RESOURCE_2"));

    uint256 public constant ROLE_A = 1 << 0; // First nybble (bits 0-3)
    uint256 public constant ROLE_B = 1 << 4; // Second nybble (bits 4-7)
    uint256 public constant ROLE_C = 1 << 8; // Third nybble (bits 8-11)
    uint256 public constant ROLE_D = 1 << 12; // Fourth nybble (bits 12-15)
    uint256 public constant ADMIN_ROLE_A = ROLE_A << 128; // First admin nybble (bits 128-131)
    uint256 public constant ADMIN_ROLE_B = ROLE_B << 128; // Second admin nybble (bits 132-135)
    uint256 public constant ADMIN_ROLE_C = ROLE_C << 128; // Third admin nybble (bits 136-139)
    uint256 public constant ADMIN_ROLE_D = ROLE_D << 128; // Fourth admin nybble (bits 140-143)
}

contract MockEnhancedAccessControl is EnhancedAccessControl, MockRoles {
    uint256 public lastGrantedCount;
    uint256 public lastGrantedRoleBitmap;
    uint256 public lastGrantedUpdatedRoles;
    uint256 public lastGrantedOldRoles;
    uint256 public lastGrantedNewRoles;
    address public lastGrantedAccount;
    uint256 public lastGrantedResource;

    uint256 public lastRevokedCount;
    uint256 public lastRevokedRoleBitmap;
    uint256 public lastRevokedUpdatedRoles;
    uint256 public lastRevokedOldRoles;
    uint256 public lastRevokedNewRoles;
    address public lastRevokedAccount;
    uint256 public lastRevokedResource;

    constructor() EnhancedAccessControl() {
        _grantRoles(
            ROOT_RESOURCE,
            ROLE_A |
                ROLE_B |
                ROLE_C |
                ROLE_D |
                ADMIN_ROLE_A |
                ADMIN_ROLE_B |
                ADMIN_ROLE_C |
                ADMIN_ROLE_D,
            msg.sender,
            true
        );
        lastGrantedCount = 0;
        lastRevokedCount = 0;
        lastGrantedResource = 0;
        lastRevokedResource = 0;
        lastGrantedRoleBitmap = 0;
        lastRevokedRoleBitmap = 0;
        lastGrantedUpdatedRoles = 0;
        lastRevokedUpdatedRoles = 0;
        lastGrantedOldRoles = 0;
        lastGrantedNewRoles = 0;
        lastRevokedOldRoles = 0;
        lastRevokedNewRoles = 0;
        lastGrantedAccount = address(0);
    }

    function callOnlyRootRoles(uint256 roleBitmap) external onlyRootRoles(roleBitmap) {
        // Function that will revert if caller doesn't have the roles in root resource
    }

    function transferRoles(uint256 resource, address srcAccount, address dstAccount) external {
        _transferRoles(resource, srcAccount, dstAccount, true);
    }

    function revokeAllRoles(uint256 resource, address account) external returns (bool) {
        return _revokeAllRoles(resource, account, true);
    }

    function _onRolesGranted(
        uint256 resource,
        address account,
        uint256 oldRoles,
        uint256 newRoles,
        uint256 roleBitmap
    ) internal override {
        lastGrantedCount++;
        lastGrantedResource = resource;
        lastGrantedRoleBitmap = roleBitmap;
        lastGrantedOldRoles = oldRoles;
        lastGrantedNewRoles = newRoles;
        lastGrantedUpdatedRoles = newRoles;
        lastGrantedAccount = account;
    }

    function _onRolesRevoked(
        uint256 resource,
        address account,
        uint256 oldRoles,
        uint256 newRoles,
        uint256 roleBitmap
    ) internal override {
        lastRevokedCount++;
        lastRevokedResource = resource;
        lastRevokedRoleBitmap = roleBitmap;
        lastRevokedOldRoles = oldRoles;
        lastRevokedNewRoles = newRoles;
        lastRevokedUpdatedRoles = newRoles;
        lastRevokedAccount = account;
    }

    function grantRolesWithoutCallback(
        uint256 resource,
        uint256 roleBitmap,
        address account
    ) external canGrantRoles(resource, roleBitmap) returns (bool) {
        if (resource == ROOT_RESOURCE) {
            revert EACRootResourceNotAllowed();
        }
        return _grantRoles(resource, roleBitmap, account, false);
    }

    function revokeRolesWithoutCallback(
        uint256 resource,
        uint256 roleBitmap,
        address account
    ) external canRevokeRoles(resource, roleBitmap) returns (bool) {
        if (resource == ROOT_RESOURCE) {
            revert EACRootResourceNotAllowed();
        }
        return _revokeRoles(resource, roleBitmap, account, false);
    }

    function transferRolesWithoutCallback(
        uint256 resource,
        address srcAccount,
        address dstAccount
    ) external {
        _transferRoles(resource, srcAccount, dstAccount, false);
    }

    function revokeAllRolesWithoutCallback(
        uint256 resource,
        address account
    ) external returns (bool) {
        return _revokeAllRoles(resource, account, false);
    }

    // Test helpers that bypass all authorization checks to test core logic
    function grantRolesDirect(
        uint256 resource,
        uint256 roleBitmap,
        address account
    ) external returns (bool) {
        return _grantRoles(resource, roleBitmap, account, false);
    }

    function revokeRolesDirect(
        uint256 resource,
        uint256 roleBitmap,
        address account
    ) external returns (bool) {
        return _revokeRoles(resource, roleBitmap, account, false);
    }
}

contract EnhancedAccessControlTest is Test, MockRoles {
    MockEnhancedAccessControl access;
    address admin;
    address user1;
    address user2;
    address superuser;

    function setUp() public {
        admin = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        superuser = makeAddr("superuser");
        access = new MockEnhancedAccessControl();
    }

    function test_initial_roles() public view {
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B | ROLE_C | ADMIN_ROLE_A, admin));
    }

    function test_grant_roles() public {
        vm.recordLogs();

        // Create a bitmap with regular roles only (admin roles cannot be granted via grantRoles)
        uint256 roleBitmap = ROLE_A | ROLE_B;

        access.grantRoles(RESOURCE_1, roleBitmap, user1);

        // Verify all roles were granted
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B, user1));

        // Verify roles were not granted for other resources
        assertFalse(access.hasRoles(RESOURCE_2, ROLE_A, user1));
        assertFalse(access.hasRoles(RESOURCE_2, ROLE_B, user1));
        assertFalse(access.hasRoles(RESOURCE_2, ADMIN_ROLE_A, user1));
        assertFalse(access.hasRoles(RESOURCE_2, ADMIN_ROLE_B, user1));

        // Verify events were emitted
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);

        assertEq(entries[0].topics[0], keccak256("EACRolesGranted(uint256,uint256,address)"));
        (uint256 resource, uint256 emittedRoleBitmap, address account) = abi.decode(
            entries[0].data,
            (uint256, uint256, address)
        );
        assertEq(resource, RESOURCE_1);
        assertEq(emittedRoleBitmap, roleBitmap);
        assertEq(account, user1);

        // Test granting roles that are already granted (should not emit events)
        vm.recordLogs();
        access.grantRoles(RESOURCE_1, roleBitmap, user1);
        entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);

        // Test granting a mix of new and existing roles (regular roles only)
        vm.recordLogs();
        uint256 mixedRoleBitmap = ROLE_B | ROLE_C;

        access.grantRoles(RESOURCE_1, mixedRoleBitmap, user1);

        entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        (uint256 resource2, uint256 emittedRoleBitmap2, address account2) = abi.decode(
            entries[0].data,
            (uint256, uint256, address)
        );
        assertEq(resource2, RESOURCE_1);
        assertEq(emittedRoleBitmap2, mixedRoleBitmap); // The event emits the full bitmap passed to the function
        assertEq(account2, user1);
    }

    // Test that unauthorized accounts cannot grant roles
    function test_grant_roles_unauthorized_admin() public {
        // Grant ROLE_A (but not ADMIN_ROLE_A) to user1
        access.grantRoles(RESOURCE_1, ROLE_A, user1);

        // Verify user1 has the roles
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));

        // user1 attempts to grant ROLE_A which requires ADMIN_ROLE_A admin
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACCannotGrantRoles.selector,
                RESOURCE_1,
                ROLE_A,
                user1
            )
        );
        vm.prank(user1);
        access.grantRoles(RESOURCE_1, ROLE_A, user2);
    }

    // Test that authorized accounts can grant roles
    function test_grant_roles_authorized_admin() public {
        // Grant regular role via grantRoles and admin role via direct method
        access.grantRoles(RESOURCE_1, ROLE_A, user1);
        access.grantRolesDirect(access.ROOT_RESOURCE(), ADMIN_ROLE_A, user1);

        // Verify user1 has the roles
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertTrue(access.hasRootRoles(ADMIN_ROLE_A, user1));

        // user1 attempts to grant ROLE_A which requires ADMIN_ROLE_A admin
        vm.prank(user1);
        access.grantRoles(RESOURCE_1, ROLE_A, user2);

        // Verify user2 has the roles
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user2));
    }

    function test_grant_roles_return_value() public {
        uint256 roleBitmap = ROLE_A | ROLE_B;

        bool success = access.grantRoles(RESOURCE_1, roleBitmap, user1);
        assertTrue(success);

        // Granting an already granted role should return false
        success = access.grantRoles(RESOURCE_1, roleBitmap, user1);
        assertFalse(success);
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B, user1));
    }

    // Test that grantRoles cannot be called with ROOT_RESOURCE
    function test_grant_roles_with_root_resource_not_allowed() public {
        uint256 rootResource = access.ROOT_RESOURCE();
        // Attempt to call grantRoles with ROOT_RESOURCE should revert
        vm.expectRevert(
            abi.encodeWithSelector(IEnhancedAccessControl.EACRootResourceNotAllowed.selector)
        );
        access.grantRoles(rootResource, ROLE_A, user1);
    }

    function test_root_resource_role_applies_to_all_resources() public {
        access.grantRootRoles(ROLE_A, user1);

        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertTrue(access.hasRoles(RESOURCE_2, ROLE_A, user1));
        assertTrue(access.hasRoles(uint256(keccak256("ANY_OTHER_RESOURCE")), ROLE_A, user1));
    }

    function test_has_root_roles() public {
        // Initially user1 doesn't have the role in root resource
        assertFalse(access.hasRootRoles(ROLE_A, user1));

        // Grant role in root resource using ADMIN_ROLE_A as admin
        access.grantRootRoles(ROLE_A, user1);

        // Verify user1 have the role in root resource
        assertTrue(access.hasRootRoles(ROLE_A | ROLE_A, user1));

        // Revoking the role should remove it
        access.revokeRootRoles(ROLE_A, user1);
        assertFalse(access.hasRootRoles(ROLE_A, user1));

        // Having a role in a specific resource doesn't mean having it in root resource
        access.grantRoles(RESOURCE_1, ROLE_A, user1);
        assertFalse(access.hasRootRoles(ROLE_A, user1));
    }

    function test_only_root_roles() public {
        // Grant role in root resource to user1
        access.grantRootRoles(ROLE_A, user1);

        // User1 should be able to call function with onlyRootRoles modifier
        vm.prank(user1);
        access.callOnlyRootRoles(ROLE_A);

        // User2 doesn't have the role, should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                access.ROOT_RESOURCE(),
                ROLE_A,
                user2
            )
        );
        vm.prank(user2);
        access.callOnlyRootRoles(ROLE_A);

        // Having the role in a specific resource doesn't satisfy onlyRootRoles
        access.grantRoles(RESOURCE_1, ROLE_A, user2);

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                access.ROOT_RESOURCE(),
                ROLE_A,
                user2
            )
        );
        vm.prank(user2);
        access.callOnlyRootRoles(ROLE_A);
    }

    function test_has_roles_requires_all_roles() public {
        // Grant only ROLE_A and ROLE_B to user1
        access.grantRoles(RESOURCE_1, ROLE_A | ROLE_B, user1);

        // Verify individual roles work
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_B, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_C, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_D, user1));

        // Verify combinations with only granted roles work
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B, user1));

        // Verify combinations with at least one missing role fail
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_C, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_B | ROLE_D, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B | ROLE_C, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B | ROLE_C | ROLE_D, user1));

        // Grant one more role and test again
        access.grantRoles(RESOURCE_1, ROLE_C | ROLE_D, user1);

        // Verify combinations with A, B, C and D work
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B | ROLE_C | ROLE_D, user1));
    }

    function test_has_root_roles_requires_all_roles() public {
        // Grant only ROLE_A and ROLE_B to user1 in root resource
        access.grantRootRoles(ROLE_A | ROLE_B, user1);

        // Verify individual roles work
        assertTrue(access.hasRootRoles(ROLE_A, user1));
        assertTrue(access.hasRootRoles(ROLE_B, user1));
        assertFalse(access.hasRootRoles(ROLE_C, user1));
        assertFalse(access.hasRootRoles(ROLE_D, user1));

        // Verify combinations with only granted roles work
        assertTrue(access.hasRootRoles(ROLE_A | ROLE_B, user1));

        // Verify combinations with at least one missing role fail
        assertFalse(access.hasRootRoles(ROLE_A | ROLE_C, user1));
        assertFalse(access.hasRootRoles(ROLE_B | ROLE_D, user1));
        assertFalse(access.hasRootRoles(ROLE_A | ROLE_B | ROLE_C, user1));
        assertFalse(access.hasRootRoles(ROLE_A | ROLE_B | ROLE_C | ROLE_D, user1));

        // Grant one more role and test again
        access.grantRootRoles(ROLE_C | ROLE_D, user1);

        // Verify combinations with A, B, C and D work
        assertTrue(access.hasRootRoles(ROLE_A | ROLE_B | ROLE_C | ROLE_D, user1));
    }

    function test_revoke_roles() public {
        // Grant multiple roles to user1 in different resources
        access.grantRoles(RESOURCE_1, ROLE_A, user1);
        access.grantRoles(RESOURCE_1, ROLE_B, user1);
        access.grantRoles(RESOURCE_2, ROLE_A, user1);

        // Verify initial state
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B, user1));
        assertTrue(access.hasRoles(RESOURCE_2, ROLE_A, user1));

        // Basic revocation test
        vm.recordLogs();
        bool success = access.revokeRoles(RESOURCE_1, ROLE_A, user1);

        // Verify success and role was revoked
        assertTrue(success);
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_B, user1)); // Other role shouldn't be affected

        // Verify role in other resource was not affected
        assertTrue(access.hasRoles(RESOURCE_2, ROLE_A, user1));

        // Verify event was emitted correctly
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EACRolesRevoked(uint256,uint256,address)"));
        (uint256 resource, uint256 roles, address account) = abi.decode(
            entries[0].data,
            (uint256, uint256, address)
        );
        assertEq(resource, RESOURCE_1);
        assertEq(roles, ROLE_A);
        assertEq(account, user1);

        // Test revoking a non-existent role (should not emit events)
        vm.recordLogs();
        success = access.revokeRoles(RESOURCE_1, ROLE_C, user1);

        // Verify no changes and failure return
        assertFalse(success);
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_C, user1));
        entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);

        // Test revoking a mix of existing and non-existing roles
        vm.recordLogs();

        // Create a bitmap for ROLE_B and ROLE_C with ADMIN_ROLE_B as admin
        uint256 mixedRoleBitmap = ROLE_B | ROLE_C;

        success = access.revokeRoles(RESOURCE_1, mixedRoleBitmap, user1);

        // Verify success (at least one role was revoked)
        assertTrue(success);
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_B, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_C, user1));

        // Verify event was emitted correctly
        entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EACRolesRevoked(uint256,uint256,address)"));
        (resource, roles, account) = abi.decode(entries[0].data, (uint256, uint256, address));
        assertEq(resource, RESOURCE_1);
        assertEq(roles, mixedRoleBitmap);
        assertEq(account, user1);

        // Verify roles for RESOURCE_2 were still not affected
        assertTrue(access.hasRoles(RESOURCE_2, ROLE_A, user1));
    }

    // Test that unauthorized accounts cannot revoke roles
    function test_revoke_roles_unauthorized_admin() public {
        // Grant ROLE_A to user2, as the test admin
        access.grantRoles(RESOURCE_1, ROLE_A, user2);

        // Verify user2 has ROLE_A
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user2));

        // user1 attempts to revoke ROLE_A from user2, but doesn't have ADMIN_ROLE_A admin
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACCannotRevokeRoles.selector,
                RESOURCE_1,
                ROLE_A,
                user1
            )
        );
        EnhancedAccessControl(address(access)).revokeRoles(RESOURCE_1, ROLE_A, user2);
        vm.stopPrank();

        // Verify user2 still has ROLE_A (it wasn't revoked)
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user2));
    }

    // Test that authorized accounts can revoke roles
    function test_revoke_roles_authorized_admin() public {
        // Grant ROLE_A to user2, as the test admin
        access.grantRoles(RESOURCE_1, ROLE_A, user2);

        // Verify user2 has ROLE_A
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user2));

        // Grant admin role to user1 via direct method
        access.grantRolesDirect(access.ROOT_RESOURCE(), ADMIN_ROLE_A, user1);
        // user1 attempts to revoke ROLE_A from user2, which should succeed since user1 has ADMIN_ROLE_A
        vm.prank(user1);
        access.revokeRoles(RESOURCE_1, ROLE_A, user2);

        // Verify user2 no longer has ROLE_A
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A, user2));
    }

    // Test that revokeRoles cannot be called with ROOT_RESOURCE
    function test_revoke_roles_with_root_resource_not_allowed() public {
        uint256 rootResource = access.ROOT_RESOURCE();
        // Attempt to call revokeRoles with ROOT_RESOURCE should revert
        vm.expectRevert(
            abi.encodeWithSelector(IEnhancedAccessControl.EACRootResourceNotAllowed.selector)
        );
        access.revokeRoles(rootResource, ROLE_A, user1);
    }

    function test_revoke_root_roles() public {
        // Grant roles to user1 in the root resource
        access.grantRootRoles(ROLE_A | ROLE_B, user1);

        // Verify initial state
        assertTrue(access.hasRootRoles(ROLE_A | ROLE_B, user1));

        // Record logs to verify event emission
        vm.recordLogs();

        // Revoke one role from root resource
        bool success = access.revokeRootRoles(ROLE_A, user1);

        // Verify success and role was revoked
        assertTrue(success);
        assertFalse(access.hasRootRoles(ROLE_A, user1));
        assertTrue(access.hasRootRoles(ROLE_B, user1)); // Other role shouldn't be affected

        // Verify event was emitted correctly
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EACRolesRevoked(uint256,uint256,address)"));
        (uint256 resource, uint256 roles, address account) = abi.decode(
            entries[0].data,
            (uint256, uint256, address)
        );
        assertEq(resource, access.ROOT_RESOURCE());
        assertEq(roles, ROLE_A);
        assertEq(account, user1);

        // Test revoking a non-existent role (should not emit events)
        vm.recordLogs();
        success = access.revokeRootRoles(ROLE_C, user1);

        // Verify no changes and failure return
        assertFalse(success);
        entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);

        // Test revoking all remaining roles
        vm.recordLogs();
        success = access.revokeRootRoles(ROLE_B, user1);

        // Verify success
        assertTrue(success);
        assertFalse(access.hasRootRoles(ROLE_B, user1));

        // Verify event was emitted correctly
        entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
    }

    function test_revoke_root_roles_unauthorized_admin() public {
        // Grant ROLE_A to user2 in root resource, as the test admin
        access.grantRootRoles(ROLE_A, user2);

        // Verify user2 has ROLE_A in root resource
        assertTrue(access.hasRootRoles(ROLE_A, user2));

        // user1 attempts to revoke ROLE_A from user2, but doesn't have ADMIN_ROLE_A admin
        vm.startPrank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACCannotRevokeRoles.selector,
                access.ROOT_RESOURCE(),
                ROLE_A,
                user1
            )
        );
        EnhancedAccessControl(address(access)).revokeRootRoles(ROLE_A, user2);
        vm.stopPrank();

        // Verify user2 still has ROLE_A (it wasn't revoked)
        assertTrue(access.hasRootRoles(ROLE_A, user2));
    }

    function test_revoke_root_roles_authorized_admin() public {
        // Grant ROLE_A to user2 in root resource, as the test admin
        access.grantRootRoles(ROLE_A, user2);

        // Verify user2 has ROLE_A in root resource
        assertTrue(access.hasRootRoles(ROLE_A, user2));

        // Grant admin role to user1 in root resource
        access.grantRolesDirect(access.ROOT_RESOURCE(), ADMIN_ROLE_A, user1);

        // user1 attempts to revoke ROLE_A from user2
        vm.prank(user1);
        access.revokeRootRoles(ROLE_A, user2);

        // Verify user2 no longer has ROLE_A in root resource
        assertFalse(access.hasRootRoles(ROLE_A, user2));
    }

    function test_revoke_all_roles() public {
        // Setup: Grant multiple roles to user1
        access.grantRoles(RESOURCE_1, ROLE_A, user1);
        access.grantRoles(RESOURCE_1, ROLE_B, user1);
        access.grantRoles(RESOURCE_2, ROLE_A, user1);

        // Verify initial state
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B, user1));
        assertTrue(access.hasRoles(RESOURCE_2, ROLE_A, user1));

        // Record logs to verify event emission
        vm.recordLogs();

        // Revoke all roles for RESOURCE_1
        bool success = access.revokeAllRoles(RESOURCE_1, user1);

        // Verify the operation was successful
        assertTrue(success);

        // Verify all roles for RESOURCE_1 were revoked
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_B, user1));

        // Verify roles for RESOURCE_2 were not affected
        assertTrue(access.hasRoles(RESOURCE_2, ROLE_A, user1));

        // Verify event was emitted correctly
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EACRolesRevoked(uint256,uint256,address)"));
        (uint256 resource, uint256 roles, address account) = abi.decode(
            entries[0].data,
            (uint256, uint256, address)
        );
        assertEq(resource, RESOURCE_1);
        assertTrue((roles & ROLE_A) == ROLE_A);
        assertTrue((roles & ROLE_B) == ROLE_B);
        assertEq(account, user1);

        // Test revoking all roles when there are no roles to revoke
        vm.recordLogs();
        success = access.revokeAllRoles(RESOURCE_1, user1);

        // Verify the operation was not successful (no roles to revoke)
        assertFalse(success);

        // Verify no event was emitted
        entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
    }

    function test_supports_interface() public view {
        assertTrue(access.supportsInterface(type(IEnhancedAccessControl).interfaceId));
    }

    function test_transfer_roles() public {
        // Setup: Grant multiple roles to user1
        access.grantRoles(RESOURCE_1, ROLE_B, user1);
        access.grantRoles(RESOURCE_1, ROLE_A, user1);
        access.grantRoles(RESOURCE_2, ROLE_A, user1);

        // Verify initial state
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B, user1));
        assertTrue(access.hasRoles(RESOURCE_2, ROLE_A, user1));

        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A, user2));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_B, user2));
        assertFalse(access.hasRoles(RESOURCE_2, ROLE_A, user2));

        // Record logs to verify event emission
        vm.recordLogs();

        // Transfer roles from user1 to user2 for RESOURCE_1
        access.transferRoles(RESOURCE_1, user1, user2);

        // Verify roles were transferred correctly for RESOURCE_1
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B, user2));

        // Verify roles for RESOURCE_2 were not transferred
        assertFalse(access.hasRoles(RESOURCE_2, ROLE_A, user2));

        // Verify user1 no longer has roles in RESOURCE_1 (transferred away)
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B, user1));
        // But still has roles in RESOURCE_2 (not transferred)
        assertTrue(access.hasRoles(RESOURCE_2, ROLE_A, user1));

        // Verify events were emitted correctly (both revoke and grant)
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 2);

        // First event should be EACRolesRevoked for user1
        assertEq(entries[0].topics[0], keccak256("EACRolesRevoked(uint256,uint256,address)"));
        (uint256 resource1, uint256 roleBitmap1, address account1) = abi.decode(
            entries[0].data,
            (uint256, uint256, address)
        );
        assertEq(resource1, RESOURCE_1);
        assertEq(account1, user1);
        assertTrue((roleBitmap1 & ROLE_A) == ROLE_A);
        assertTrue((roleBitmap1 & ROLE_B) == ROLE_B);

        // Second event should be EACRolesGranted for user2
        assertEq(entries[1].topics[0], keccak256("EACRolesGranted(uint256,uint256,address)"));
        (uint256 resource2, uint256 roleBitmap2, address account2) = abi.decode(
            entries[1].data,
            (uint256, uint256, address)
        );
        assertEq(resource2, RESOURCE_1);
        assertEq(account2, user2);
        assertTrue((roleBitmap2 & ROLE_A) == ROLE_A);
        assertTrue((roleBitmap2 & ROLE_B) == ROLE_B);
    }

    function test_transfer_roles_with_existing_roles() public {
        // Setup: Grant different roles to user1 and user2
        access.grantRoles(RESOURCE_1, ROLE_A, user1);
        access.grantRoles(RESOURCE_1, ROLE_B, user1);
        access.grantRoles(RESOURCE_1, ROLE_C, user2);
        access.grantRoles(RESOURCE_1, ROLE_D, user2);

        // Verify initial state
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B, user1));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_C | ROLE_D, user2));

        // Record logs to verify event emission
        vm.recordLogs();

        // Transfer roles from user1 to user2 for RESOURCE_1
        // This should OR the roles from user1 with user2's existing roles
        access.transferRoles(RESOURCE_1, user1, user2);

        // Verify user1 no longer has their original roles (transferred away)
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B, user1));

        // Verify user2 has all roles (original + transferred)
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B | ROLE_C | ROLE_D, user2));

        // Verify events were emitted correctly (both revoke and grant)
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 2);

        // First event should be EACRolesRevoked for user1
        assertEq(entries[0].topics[0], keccak256("EACRolesRevoked(uint256,uint256,address)"));
        (uint256 resource1, uint256 roleBitmap1, address account1) = abi.decode(
            entries[0].data,
            (uint256, uint256, address)
        );
        assertEq(resource1, RESOURCE_1);
        assertEq(account1, user1);
        assertTrue((roleBitmap1 & ROLE_A) == ROLE_A);
        assertTrue((roleBitmap1 & ROLE_B) == ROLE_B);

        // Second event should be EACRolesGranted for user2
        assertEq(entries[1].topics[0], keccak256("EACRolesGranted(uint256,uint256,address)"));
        (uint256 resource2, uint256 roleBitmap2, address account2) = abi.decode(
            entries[1].data,
            (uint256, uint256, address)
        );
        assertEq(resource2, RESOURCE_1);
        assertEq(account2, user2);
        assertTrue((roleBitmap2 & ROLE_A) == ROLE_A);
        assertTrue((roleBitmap2 & ROLE_B) == ROLE_B);
    }

    function test_transfer_roles_with_admin_roles() public {
        // Setup: Grant roles including admin roles to user1
        // Regular roles must be granted via grantRoles
        access.grantRoles(RESOURCE_1, ROLE_A | ROLE_B, user1);
        // Admin roles must be granted via direct method (due to our new restrictions)
        access.grantRolesDirect(access.ROOT_RESOURCE(), ADMIN_ROLE_A | ADMIN_ROLE_B, user1);

        // Grant admin roles directly in the specific resource for testing transfer
        // We need to use the internal method since public grantRoles blocks admin roles
        access.grantRolesDirect(RESOURCE_1, ADMIN_ROLE_C, user1);

        // Setup user2 with some existing roles
        access.grantRoles(RESOURCE_1, ROLE_C, user2);
        access.grantRolesDirect(RESOURCE_1, ADMIN_ROLE_D, user2);

        // Verify initial state
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B, user1));
        assertTrue(access.hasRoles(RESOURCE_1, ADMIN_ROLE_A | ADMIN_ROLE_B, user1)); // From root resource
        assertTrue(access.hasRoles(RESOURCE_1, ADMIN_ROLE_C, user1)); // Direct in resource
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_C, user2));
        assertTrue(access.hasRoles(RESOURCE_1, ADMIN_ROLE_D, user2));

        // Record logs to verify event emission
        vm.recordLogs();

        // Transfer roles from user1 to user2 for RESOURCE_1
        // This should transfer all roles that user1 has directly in RESOURCE_1
        // (but not the root resource roles)
        access.transferRoles(RESOURCE_1, user1, user2);

        // Verify user1 no longer has roles directly in RESOURCE_1
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ADMIN_ROLE_C, user1));
        // But should still have admin roles from root resource
        assertTrue(access.hasRoles(RESOURCE_1, ADMIN_ROLE_A | ADMIN_ROLE_B, user1)); // From root resource

        // Verify user2 has all transferred roles plus original roles
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B | ROLE_C, user2)); // Regular roles
        assertTrue(access.hasRoles(RESOURCE_1, ADMIN_ROLE_C | ADMIN_ROLE_D, user2)); // Admin roles

        // Verify events were emitted correctly (both revoke and grant)
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 2);

        // First event should be EACRolesRevoked for user1
        assertEq(entries[0].topics[0], keccak256("EACRolesRevoked(uint256,uint256,address)"));
        (uint256 resource1, uint256 roleBitmap1, address account1) = abi.decode(
            entries[0].data,
            (uint256, uint256, address)
        );
        assertEq(resource1, RESOURCE_1);
        assertEq(account1, user1);
        assertTrue((roleBitmap1 & ROLE_A) == ROLE_A);
        assertTrue((roleBitmap1 & ROLE_B) == ROLE_B);
        assertTrue((roleBitmap1 & ADMIN_ROLE_C) == ADMIN_ROLE_C); // Admin role was transferred

        // Second event should be EACRolesGranted for user2
        assertEq(entries[1].topics[0], keccak256("EACRolesGranted(uint256,uint256,address)"));
        (uint256 resource2, uint256 roleBitmap2, address account2) = abi.decode(
            entries[1].data,
            (uint256, uint256, address)
        );
        assertEq(resource2, RESOURCE_1);
        assertEq(account2, user2);
        assertTrue((roleBitmap2 & ROLE_A) == ROLE_A);
        assertTrue((roleBitmap2 & ROLE_B) == ROLE_B);
        assertTrue((roleBitmap2 & ADMIN_ROLE_C) == ADMIN_ROLE_C); // Admin role was transferred
    }

    function test_role_callback_hooks() public {
        // Test granting roles
        uint256 roleBitmap = ROLE_A | ROLE_B;
        access.grantRoles(RESOURCE_1, roleBitmap, user1);

        // Verify grant callback was called with correct parameters
        assertEq(access.lastGrantedResource(), RESOURCE_1);
        assertEq(access.lastGrantedRoleBitmap(), roleBitmap);
        assertEq(access.lastGrantedOldRoles(), 0);
        assertEq(access.lastGrantedNewRoles(), roleBitmap);
        assertEq(access.lastGrantedUpdatedRoles(), roleBitmap);
        assertEq(access.lastGrantedAccount(), user1);
        assertEq(access.lastGrantedCount(), 1);

        // Test revoking roles
        access.revokeRoles(RESOURCE_1, ROLE_A, user1);

        // Verify revoke callback was called with correct parameters
        assertEq(access.lastRevokedResource(), RESOURCE_1);
        assertEq(access.lastRevokedRoleBitmap(), ROLE_A);
        assertEq(access.lastRevokedOldRoles(), roleBitmap);
        assertEq(access.lastRevokedNewRoles(), ROLE_B);
        assertEq(access.lastRevokedUpdatedRoles(), ROLE_B); // Only ROLE_B remains
        assertEq(access.lastRevokedAccount(), user1);
        assertEq(access.lastRevokedCount(), 1);

        // Test granting roles that already exist (should not trigger callback)
        uint256 prevGrantedResource = access.lastGrantedResource();
        uint256 prevGrantedRoleBitmap = access.lastGrantedRoleBitmap();
        uint256 prevGrantedCount = access.lastGrantedCount();

        access.grantRoles(RESOURCE_1, ROLE_B, user1);

        // Verify callback was not called (values remain unchanged)
        assertEq(access.lastGrantedResource(), prevGrantedResource);
        assertEq(access.lastGrantedRoleBitmap(), prevGrantedRoleBitmap);
        assertEq(access.lastGrantedCount(), prevGrantedCount);

        // Test revoking all roles
        access.revokeAllRoles(RESOURCE_1, user1);

        // Verify revoke callback was called with correct parameters
        assertEq(access.lastRevokedResource(), RESOURCE_1);
        assertEq(access.lastRevokedRoleBitmap(), EACBaseRolesLib.ALL_ROLES);
        assertEq(access.lastRevokedOldRoles(), ROLE_B);
        assertEq(access.lastRevokedNewRoles(), 0);
        assertEq(access.lastRevokedUpdatedRoles(), 0); // No roles remain
        assertEq(access.lastRevokedAccount(), user1);
        assertEq(access.lastRevokedCount(), 2);

        // Test transferring roles
        access.grantRoles(RESOURCE_1, ROLE_A | ROLE_B, user1);

        // Store callback state before transfer since transferRoles uses executeCallbacks=true
        uint256 countBeforeTransfer = access.lastGrantedCount();
        uint256 revokeCountBeforeTransfer = access.lastRevokedCount();

        access.transferRoles(RESOURCE_1, user1, user2);

        // Verify both revoke and grant callbacks were called for the transfer operation
        // First the revoke callback for user1
        assertEq(access.lastRevokedResource(), RESOURCE_1);
        assertEq(access.lastRevokedRoleBitmap(), ROLE_A | ROLE_B);
        assertEq(access.lastRevokedOldRoles(), ROLE_A | ROLE_B);
        assertEq(access.lastRevokedNewRoles(), 0);
        assertEq(access.lastRevokedUpdatedRoles(), 0);
        assertEq(access.lastRevokedAccount(), user1);
        assertEq(access.lastRevokedCount(), revokeCountBeforeTransfer + 1);

        // Then the grant callback for user2
        assertEq(access.lastGrantedResource(), RESOURCE_1);
        assertEq(access.lastGrantedRoleBitmap(), ROLE_A | ROLE_B);
        assertEq(access.lastGrantedOldRoles(), 0);
        assertEq(access.lastGrantedNewRoles(), ROLE_A | ROLE_B);
        assertEq(access.lastGrantedUpdatedRoles(), ROLE_A | ROLE_B);
        assertEq(access.lastGrantedAccount(), user2);
        assertEq(access.lastGrantedCount(), countBeforeTransfer + 1);
    }

    function test_disable_callbacks() public {
        // Store initial counter values
        uint256 initialGrantCount = access.lastGrantedCount();
        uint256 initialRevokeCount = access.lastRevokedCount();

        // Test granting roles without callback
        access.grantRolesWithoutCallback(RESOURCE_1, ROLE_A, user1);

        // Verify grant callback was not called (counter unchanged)
        assertEq(access.lastGrantedCount(), initialGrantCount);

        // But the role should be granted
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));

        // Test revoking roles without callback
        access.revokeRolesWithoutCallback(RESOURCE_1, ROLE_A, user1);

        // Verify revoke callback was not called (counter unchanged)
        assertEq(access.lastRevokedCount(), initialRevokeCount);

        // But the role should be revoked
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A, user1));

        // Test transferRoles without callback
        access.grantRoles(RESOURCE_1, ROLE_A | ROLE_B, user1);
        uint256 grantCountBeforeTransfer = access.lastGrantedCount();
        uint256 revokeCountBeforeTransfer = access.lastRevokedCount();

        access.transferRolesWithoutCallback(RESOURCE_1, user1, user2);

        // Verify neither revoke nor grant callbacks were called for the transfer
        assertEq(access.lastGrantedCount(), grantCountBeforeTransfer);
        assertEq(access.lastRevokedCount(), revokeCountBeforeTransfer);

        // But the roles should be transferred
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B, user1)); // Revoked from user1
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B, user2)); // Granted to user2

        // Test revokeAllRoles without callback
        uint256 revokeCountBeforeRevokeAll = access.lastRevokedCount();

        access.revokeAllRolesWithoutCallback(RESOURCE_1, user1);

        // Verify revoke callback was not called
        assertEq(access.lastRevokedCount(), revokeCountBeforeRevokeAll);

        // But all roles should be revoked
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B, user1));
    }

    function test_direct_roles_access() public {
        // Test direct access to roles mapping
        uint256 roleBitmap = ROLE_A | ROLE_B;

        // Grant roles to user1
        access.grantRoles(RESOURCE_1, roleBitmap, user1);

        // Verify direct access to the roles mapping matches hasRoles results
        assertTrue(access.hasRoles(RESOURCE_1, roleBitmap, user1));
        assertEq(access.roles(RESOURCE_1, user1), roleBitmap);

        // Verify root resource roles
        access.grantRootRoles(ROLE_C, user1);
        assertTrue(access.hasRootRoles(ROLE_C, user1));
        assertEq(access.roles(access.ROOT_RESOURCE(), user1), ROLE_C);

        // Check that roles in different resources are distinct
        assertFalse(access.hasRootRoles(ROLE_A, user1));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertTrue((access.roles(RESOURCE_1, user1) & ROLE_A) == ROLE_A);
        assertTrue((access.roles(access.ROOT_RESOURCE(), user1) & ROLE_A) == 0);

        // Verify role removal affects the mapping correctly
        access.revokeRoles(RESOURCE_1, ROLE_A, user1);
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_B, user1));
        assertEq(access.roles(RESOURCE_1, user1), ROLE_B);

        // Test that revoking all roles clears the mapping entry
        access.revokeAllRoles(RESOURCE_1, user1);
        assertEq(access.roles(RESOURCE_1, user1), 0);

        // Root resource roles should still exist
        assertEq(access.roles(access.ROOT_RESOURCE(), user1), ROLE_C);
    }

    function test_roles_mapping_after_operations() public {
        // Test mapping state after complex operations

        // Set up initial roles
        access.grantRoles(RESOURCE_1, ROLE_A | ROLE_B, user1);
        access.grantRoles(RESOURCE_2, ROLE_C, user1);
        access.grantRootRoles(ROLE_D, user1);

        // Verify initial state directly from the mapping
        assertEq(access.roles(RESOURCE_1, user1), ROLE_A | ROLE_B);
        assertEq(access.roles(RESOURCE_2, user1), ROLE_C);
        assertEq(access.roles(access.ROOT_RESOURCE(), user1), ROLE_D);

        // Add another user with roles
        access.grantRoles(RESOURCE_1, ROLE_C | ROLE_D, user2);
        assertEq(access.roles(RESOURCE_1, user2), ROLE_C | ROLE_D);

        // Transfer roles and verify
        access.transferRoles(RESOURCE_1, user1, user2);
        assertEq(access.roles(RESOURCE_1, user2), ROLE_A | ROLE_B | ROLE_C | ROLE_D);

        // Verify user1 no longer has RESOURCE_1 roles (transferred away)
        assertEq(access.roles(RESOURCE_1, user1), 0);

        // Verify root resource roles from user1 were not transferred
        assertTrue((access.roles(access.ROOT_RESOURCE(), user2) & ROLE_D) == 0);

        // Test that mapping is not affected for non-existent user
        assertEq(access.roles(RESOURCE_1, address(0x123)), 0);
    }

    function test_roles_mapping_consistency() public {
        // Test consistency between hasRoles and direct mapping access

        // Grant multiple roles to user1
        access.grantRoles(RESOURCE_1, ROLE_A | ROLE_B | ROLE_C, user1);
        access.grantRootRoles(ROLE_D, user1);

        // Verify consistency for normal resource
        bool directCheck = (access.roles(RESOURCE_1, user1) & (ROLE_A | ROLE_B)) ==
            (ROLE_A | ROLE_B);
        bool helperCheck = access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B, user1);
        assertEq(directCheck, helperCheck);

        // Verify consistency with root resource logic
        // hasRoles should also check root resource roles
        access.revokeRoles(RESOURCE_1, ROLE_A, user1);
        assertFalse((access.roles(RESOURCE_1, user1) & ROLE_A) == ROLE_A);

        // Grant the same role in root resource
        access.grantRootRoles(ROLE_A, user1);

        // hasRoles should return true for ROLE_A because it's in root resource
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));

        // But direct access to RESOURCE_1 mapping should not show ROLE_A
        assertFalse((access.roles(RESOURCE_1, user1) & ROLE_A) == ROLE_A);

        // Direct access to ROOT_RESOURCE mapping should show ROLE_A
        assertTrue((access.roles(access.ROOT_RESOURCE(), user1) & ROLE_A) == ROLE_A);
    }

    // Tests for hasAssignees() and max/min assignees functionality

    function test_hasAssignees_single_role() public {
        // Initially, no roles should have assignees
        assertFalse(access.hasAssignees(RESOURCE_1, ROLE_A));

        // Grant ROLE_A to user1
        access.grantRoles(RESOURCE_1, ROLE_A, user1);

        // Verify ROLE_A have assignees
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_A));

        // Grant ROLE_A to user2 as well
        access.grantRoles(RESOURCE_1, ROLE_A, user2);

        // ROLE_A should still have assignees
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_A));

        // Revoke ROLE_A from user1
        access.revokeRoles(RESOURCE_1, ROLE_A, user1);

        // ROLE_A should still have assignees (user2 still has it)
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_A));

        // Revoke ROLE_A from user2
        access.revokeRoles(RESOURCE_1, ROLE_A, user2);

        // Verify ROLE_A have no assignees
        assertFalse(access.hasAssignees(RESOURCE_1, ROLE_A));

        // Test with different roles
        assertFalse(access.hasAssignees(RESOURCE_1, ROLE_B));
        assertFalse(access.hasAssignees(RESOURCE_1, ROLE_C));
        assertFalse(access.hasAssignees(RESOURCE_1, ROLE_D));
    }

    function test_hasAssignees_two_roles() public {
        // Initially, neither role should have assignees
        assertFalse(access.hasAssignees(RESOURCE_1, ROLE_A | ROLE_D));
        assertFalse(access.hasAssignees(RESOURCE_1, ROLE_A));
        assertFalse(access.hasAssignees(RESOURCE_1, ROLE_D));

        // Grant ROLE_A to user1
        access.grantRoles(RESOURCE_1, ROLE_A, user1);

        // Verify hasAssignees return true for ROLE_A and for the combined bitmap
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_A));
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_A | ROLE_D)); // Returns true because ROLE_A has assignees
        assertFalse(access.hasAssignees(RESOURCE_1, ROLE_D)); // ROLE_D still has no assignees

        // Grant ROLE_D to user2
        access.grantRoles(RESOURCE_1, ROLE_D, user2);

        // Verify both roles have assignees
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_A));
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_D));
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_A | ROLE_D));

        // Grant both roles to the same user
        access.grantRoles(RESOURCE_1, ROLE_A | ROLE_D, superuser);

        // Should still work the same way
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_A));
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_D));
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_A | ROLE_D));

        // Revoke ROLE_A from all users
        access.revokeRoles(RESOURCE_1, ROLE_A, user1);
        access.revokeRoles(RESOURCE_1, ROLE_A, superuser);

        // Verify only ROLE_D have assignees
        assertFalse(access.hasAssignees(RESOURCE_1, ROLE_A));
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_D));
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_A | ROLE_D)); // Returns true because ROLE_D has assignees

        // Revoke ROLE_D from all users
        access.revokeRoles(RESOURCE_1, ROLE_D, user2);
        access.revokeRoles(RESOURCE_1, ROLE_D, superuser);

        // Verify neither role have assignees
        assertFalse(access.hasAssignees(RESOURCE_1, ROLE_A));
        assertFalse(access.hasAssignees(RESOURCE_1, ROLE_D));
        assertFalse(access.hasAssignees(RESOURCE_1, ROLE_A | ROLE_D));
    }

    function test_max_assignees_single_role() public {
        // Create 15 different user addresses
        address[] memory users = new address[](15);
        for (uint256 i = 0; i < 15; i++) {
            users[i] = makeAddr(string(abi.encodePacked("maxUser", i)));
        }

        // Grant ROLE_A to all 15 users (should work without error)
        for (uint256 i = 0; i < 15; i++) {
            access.grantRoles(RESOURCE_1, ROLE_A, users[i]);
            assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, users[i]));
        }

        // Verify hasAssignees returns true
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_A));

        // Try to grant ROLE_A to a 16th user - should revert with EACMaxAssignees
        address user16 = makeAddr("maxUser16");
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACMaxAssignees.selector,
                RESOURCE_1,
                ROLE_A
            )
        );
        access.grantRoles(RESOURCE_1, ROLE_A, user16);

        // Verify the 16th user didn't get the role
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A, user16));

        // Grant to 16th user should still fail even with admin role
        access.grantRolesDirect(access.ROOT_RESOURCE(), ADMIN_ROLE_A, user16);
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACMaxAssignees.selector,
                RESOURCE_1,
                ROLE_A
            )
        );
        vm.prank(user16);
        access.grantRoles(RESOURCE_1, ROLE_A, makeAddr("maxUser17"));
    }

    function test_max_assignees_two_roles() public {
        // Create enough users for testing
        address[] memory users = new address[](16);
        for (uint256 i = 0; i < 16; i++) {
            users[i] = makeAddr(string(abi.encodePacked("maxUser2", i)));
        }

        // Max out ROLE_A (15 users)
        for (uint256 i = 0; i < 15; i++) {
            access.grantRoles(RESOURCE_1, ROLE_A, users[i]);
        }

        // Max out ROLE_D (15 users) - can reuse same users
        for (uint256 i = 0; i < 15; i++) {
            access.grantRoles(RESOURCE_1, ROLE_D, users[i]);
        }

        // Both roles should have assignees
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_A));
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_D));
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_A | ROLE_D));

        // Try to grant ROLE_A to another user - should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACMaxAssignees.selector,
                RESOURCE_1,
                ROLE_A
            )
        );
        access.grantRoles(RESOURCE_1, ROLE_A, users[15]);

        // Try to grant ROLE_D to another user - should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACMaxAssignees.selector,
                RESOURCE_1,
                ROLE_D
            )
        );
        access.grantRoles(RESOURCE_1, ROLE_D, users[15]);

        // Try to grant both roles together to another user - should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACMaxAssignees.selector,
                RESOURCE_1,
                ROLE_A | ROLE_D
            )
        );
        access.grantRoles(RESOURCE_1, ROLE_A | ROLE_D, users[15]);

        // Remove one assignee from ROLE_A
        access.revokeRoles(RESOURCE_1, ROLE_A, users[0]);

        // Verify we be able to grant ROLE_A to someone else
        access.grantRoles(RESOURCE_1, ROLE_A, users[15]);
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, users[15]));

        // But ROLE_D should still be maxed out
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACMaxAssignees.selector,
                RESOURCE_1,
                ROLE_D
            )
        );
        access.grantRoles(RESOURCE_1, ROLE_D, makeAddr("extraUser"));
    }

    function test_min_assignees_single_role() public {
        // Initially, no assignees for ROLE_A
        assertFalse(access.hasAssignees(RESOURCE_1, ROLE_A));

        // Try to revoke ROLE_A when no one has it - should NOT revert (it's a no-op)
        // because newlyRemovedRoles will be 0
        bool success = access.revokeRoles(RESOURCE_1, ROLE_A, user1);
        assertFalse(success); // Should return false as no roles were actually revoked

        // Grant ROLE_A to user1
        access.grantRoles(RESOURCE_1, ROLE_A, user1);
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_A));

        // Verify revoke work
        success = access.revokeRoles(RESOURCE_1, ROLE_A, user1);
        assertTrue(success); // Should return true as role was actually revoked
        assertFalse(access.hasAssignees(RESOURCE_1, ROLE_A));

        // Try to revoke again from the same user - should NOT revert (it's a no-op)
        success = access.revokeRoles(RESOURCE_1, ROLE_A, user1);
        assertFalse(success); // Should return false as no roles were actually revoked

        // Try to revoke from a different user who never had the role - should NOT revert
        success = access.revokeRoles(RESOURCE_1, ROLE_A, user2);
        assertFalse(success); // Should return false as no roles were actually revoked
    }

    function test_min_assignees_two_roles() public {
        // Initially, no assignees for either role
        assertFalse(access.hasAssignees(RESOURCE_1, ROLE_A | ROLE_D));

        // Try to revoke both roles when no one has them - should NOT revert (it's a no-op)
        bool success = access.revokeRoles(RESOURCE_1, ROLE_A | ROLE_D, user1);
        assertFalse(success); // Should return false as no roles were actually revoked

        // Grant only ROLE_A to user1
        access.grantRoles(RESOURCE_1, ROLE_A, user1);

        // Try to revoke both roles - should partially succeed (only ROLE_A will be revoked)
        success = access.revokeRoles(RESOURCE_1, ROLE_A | ROLE_D, user1);
        assertTrue(success); // Should return true as at least one role was revoked
        assertFalse(access.hasAssignees(RESOURCE_1, ROLE_A)); // ROLE_A should be revoked
        assertFalse(access.hasAssignees(RESOURCE_1, ROLE_D)); // ROLE_D was never assigned

        // Grant both roles to user1
        access.grantRoles(RESOURCE_1, ROLE_A | ROLE_D, user1);
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_A | ROLE_D));

        // Verify revoking both work
        success = access.revokeRoles(RESOURCE_1, ROLE_A | ROLE_D, user1);
        assertTrue(success);
        assertFalse(access.hasAssignees(RESOURCE_1, ROLE_A | ROLE_D));

        // Try to revoke both again - should NOT revert (it's a no-op)
        success = access.revokeRoles(RESOURCE_1, ROLE_A | ROLE_D, user1);
        assertFalse(success); // Should return false as no roles were actually revoked
    }

    function test_hasAssignees_different_resources() public {
        // Test that hasAssignees works correctly across different resources

        // Grant ROLE_A to user1 in RESOURCE_1
        access.grantRoles(RESOURCE_1, ROLE_A, user1);

        // RESOURCE_1 should have assignees for ROLE_A, but RESOURCE_2 should not
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_A));
        assertFalse(access.hasAssignees(RESOURCE_2, ROLE_A));

        // Grant ROLE_A to user2 in RESOURCE_2
        access.grantRoles(RESOURCE_2, ROLE_A, user2);

        // Verify both resources have assignees for ROLE_A
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_A));
        assertTrue(access.hasAssignees(RESOURCE_2, ROLE_A));

        // Revoke from RESOURCE_1
        access.revokeRoles(RESOURCE_1, ROLE_A, user1);

        // Only RESOURCE_2 should have assignees now
        assertFalse(access.hasAssignees(RESOURCE_1, ROLE_A));
        assertTrue(access.hasAssignees(RESOURCE_2, ROLE_A));

        // Max out ROLE_A in RESOURCE_1
        address[] memory users = new address[](15);
        for (uint256 i = 0; i < 15; i++) {
            users[i] = makeAddr(string(abi.encodePacked("resUser", i)));
            access.grantRoles(RESOURCE_1, ROLE_A, users[i]);
        }

        // RESOURCE_1 should be maxed out, but we should still be able to grant in RESOURCE_2
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_A));
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACMaxAssignees.selector,
                RESOURCE_1,
                ROLE_A
            )
        );
        access.grantRoles(RESOURCE_1, ROLE_A, makeAddr("extraUser"));

        // But RESOURCE_2 should still accept new assignees
        access.grantRoles(RESOURCE_2, ROLE_A, makeAddr("resource2User"));
        assertTrue(access.hasAssignees(RESOURCE_2, ROLE_A));
    }

    function test_hasAssignees_with_root_resource() public {
        // Root resource behavior should not affect hasAssignees

        // Grant ROLE_A in root resource
        access.grantRootRoles(ROLE_A, user1);

        // hasAssignees should return true for root resource
        assertTrue(access.hasAssignees(access.ROOT_RESOURCE(), ROLE_A));

        // But hasAssignees should return false for other resources
        assertFalse(access.hasAssignees(RESOURCE_1, ROLE_A));
        assertFalse(access.hasAssignees(RESOURCE_2, ROLE_A));

        // Even though user1 has ROLE_A via root resource inheritance for other resources,
        // hasAssignees checks the specific resource's role counts
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1)); // user1 has the role via root
        assertFalse(access.hasAssignees(RESOURCE_1, ROLE_A)); // but RESOURCE_1 has no direct assignees

        // Grant ROLE_A directly in RESOURCE_1
        access.grantRoles(RESOURCE_1, ROLE_A, user2);

        // Verify RESOURCE_1 have assignees
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_A));
        assertTrue(access.hasAssignees(access.ROOT_RESOURCE(), ROLE_A));
    }

    // Tests for invalid role bitmaps (multiple bits set in a nybble)
    // These tests verify that invalid role bitmaps throw EACInvalidRoleBitmap error

    function test_invalid_role_bitmap_validation() public {
        // Test that core functions reject invalid role bitmaps
        uint256 invalidRoleA = ROLE_A | (1 << 1) | (1 << 2); // 0x7 = 0111 in first nybble
        uint256 invalidRoleB = ROLE_B | (1 << 5) | (1 << 6); // extra bits in second nybble

        // Test that hasAssignees rejects invalid bitmaps (this bypasses authorization)
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACInvalidRoleBitmap.selector,
                invalidRoleA
            )
        );
        access.hasAssignees(RESOURCE_1, invalidRoleA);

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACInvalidRoleBitmap.selector,
                invalidRoleB
            )
        );
        access.hasAssignees(RESOURCE_1, invalidRoleB);

        // Test validation through direct helper functions (these bypass authorization)
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACInvalidRoleBitmap.selector,
                invalidRoleA
            )
        );
        access.grantRolesDirect(RESOURCE_1, invalidRoleA, user1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACInvalidRoleBitmap.selector,
                invalidRoleB
            )
        );
        access.revokeRolesDirect(RESOURCE_1, invalidRoleB, user1);

        // Grant valid roles to verify the system still works correctly
        access.grantRoles(RESOURCE_1, ROLE_A | ROLE_B, user1);
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B, user1));
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_A | ROLE_B));

        // Valid operations should continue to work
        access.revokeRoles(RESOURCE_1, ROLE_A, user1);
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_B, user1));
    }

    function test_hasAssignees_comprehensive_validation() public {
        // Test hasAssignees with various valid and invalid role bitmaps

        // Grant some valid roles
        access.grantRoles(RESOURCE_1, ROLE_A | ROLE_B, user1);

        // Valid bitmaps should work
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_A));
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_A | ROLE_B));
        assertFalse(access.hasAssignees(RESOURCE_1, ROLE_C | ROLE_D));

        // Create invalid bitmaps from each nybble for comprehensive coverage
        uint256 invalidFromNybble1 = ROLE_A | (1 << 1); // extra bit in first nybble
        uint256 invalidFromNybble2 = ROLE_B | (1 << 5); // extra bit in second nybble
        uint256 invalidFromNybble3 = ROLE_C | (1 << 9); // extra bit in third nybble
        uint256 invalidFromNybble4 = ROLE_D | (1 << 13); // extra bit in fourth nybble

        // All invalid bitmaps should be rejected
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACInvalidRoleBitmap.selector,
                invalidFromNybble1
            )
        );
        access.hasAssignees(RESOURCE_1, invalidFromNybble1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACInvalidRoleBitmap.selector,
                invalidFromNybble2
            )
        );
        access.hasAssignees(RESOURCE_1, invalidFromNybble2);

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACInvalidRoleBitmap.selector,
                invalidFromNybble3
            )
        );
        access.hasAssignees(RESOURCE_1, invalidFromNybble3);

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACInvalidRoleBitmap.selector,
                invalidFromNybble4
            )
        );
        access.hasAssignees(RESOURCE_1, invalidFromNybble4);

        // Combined invalid bitmap should also be rejected
        uint256 combinedInvalid = invalidFromNybble1 | invalidFromNybble3;
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACInvalidRoleBitmap.selector,
                combinedInvalid
            )
        );
        access.hasAssignees(RESOURCE_1, combinedInvalid);
    }

    // Tests for getAssigneeCount() method

    function test_getAssigneeCount_single_role_basic() public {
        // Initially, no roles should have assignees
        (uint256 counts, uint256 mask) = access.getAssigneeCount(RESOURCE_1, ROLE_A);
        assertEq(counts, 0);
        assertEq(mask, 0xf); // ROLE_A mask should be 0xf (first nybble)

        // Grant ROLE_A to user1
        access.grantRoles(RESOURCE_1, ROLE_A, user1);

        (counts, mask) = access.getAssigneeCount(RESOURCE_1, ROLE_A);
        assertEq(counts, 1); // Should have 1 assignee
        assertEq(mask, 0xf); // Mask should remain the same

        // Grant ROLE_A to user2
        access.grantRoles(RESOURCE_1, ROLE_A, user2);

        (counts, mask) = access.getAssigneeCount(RESOURCE_1, ROLE_A);
        assertEq(counts, 2); // Should have 2 assignees
        assertEq(mask, 0xf);

        // Revoke ROLE_A from user1
        access.revokeRoles(RESOURCE_1, ROLE_A, user1);

        (counts, mask) = access.getAssigneeCount(RESOURCE_1, ROLE_A);
        assertEq(counts, 1); // Should have 1 assignee
        assertEq(mask, 0xf);

        // Revoke ROLE_A from user2
        access.revokeRoles(RESOURCE_1, ROLE_A, user2);

        (counts, mask) = access.getAssigneeCount(RESOURCE_1, ROLE_A);
        assertEq(counts, 0); // Should have 0 assignees
        assertEq(mask, 0xf);
    }

    function test_getAssigneeCount_multiple_roles() public {
        // Test with ROLE_A (first nybble) and ROLE_D (fourth nybble)
        uint256 roleBitmap = ROLE_A | ROLE_D;

        // Initially, no assignees
        (uint256 counts, uint256 mask) = access.getAssigneeCount(RESOURCE_1, roleBitmap);
        assertEq(counts, 0);
        assertEq(mask, 61455); // Should mask both first and fourth nybbles (4097 expanded to mask)

        // Grant ROLE_A to user1
        access.grantRoles(RESOURCE_1, ROLE_A, user1);

        (counts, mask) = access.getAssigneeCount(RESOURCE_1, roleBitmap);
        assertEq(counts, 1); // ROLE_A has 1, ROLE_D has 0
        assertEq(mask, 61455);

        // Grant ROLE_D to user2
        access.grantRoles(RESOURCE_1, ROLE_D, user2);

        (counts, mask) = access.getAssigneeCount(RESOURCE_1, roleBitmap);
        assertEq(counts, 1 + 4096); // ROLE_A increments by 1, ROLE_D increments by 4096
        assertEq(mask, 61455);

        // Grant both roles to superuser
        access.grantRoles(RESOURCE_1, ROLE_A | ROLE_D, superuser);

        (counts, mask) = access.getAssigneeCount(RESOURCE_1, roleBitmap);
        assertEq(counts, 2 + 8192); // ROLE_A increments by 2, ROLE_D increments by 8192
        assertEq(mask, 61455);
    }

    function test_getAssigneeCount_all_four_roles() public {
        uint256 allRoles = ROLE_A | ROLE_B | ROLE_C | ROLE_D;

        // Initially, no assignees
        (uint256 counts, uint256 mask) = access.getAssigneeCount(RESOURCE_1, allRoles);
        assertEq(counts, 0);
        assertEq(mask, 0xffff); // All four nybbles should be masked

        // Grant each role to different users
        access.grantRoles(RESOURCE_1, ROLE_A, user1);
        access.grantRoles(RESOURCE_1, ROLE_B, user2);
        access.grantRoles(RESOURCE_1, ROLE_C, superuser);

        (counts, mask) = access.getAssigneeCount(RESOURCE_1, allRoles);
        assertEq(counts, 0x111); // ROLE_A=1, ROLE_B=1, ROLE_C=1, ROLE_D=0
        assertEq(mask, 0xffff);

        // Grant ROLE_D to admin and add more assignees
        access.grantRoles(RESOURCE_1, ROLE_D, admin);
        access.grantRoles(RESOURCE_1, ROLE_A, user2); // user2 has ROLE_A and ROLE_B

        (counts, mask) = access.getAssigneeCount(RESOURCE_1, allRoles);
        assertEq(counts, 2 + 16 + 256 + 4096); // ROLE_A=2, ROLE_B=1, ROLE_C=1, ROLE_D=1
        assertEq(mask, 0xffff);
    }

    function test_getAssigneeCount_different_resources() public {
        // Test that getAssigneeCount works correctly across different resources

        // Grant ROLE_A to user1 in RESOURCE_1
        access.grantRoles(RESOURCE_1, ROLE_A, user1);

        (uint256 counts1, uint256 mask1) = access.getAssigneeCount(RESOURCE_1, ROLE_A);
        (uint256 counts2, uint256 mask2) = access.getAssigneeCount(RESOURCE_2, ROLE_A);

        assertEq(counts1, 1); // RESOURCE_1 should have 1 assignee
        assertEq(counts2, 0); // RESOURCE_2 should have 0 assignees
        assertEq(mask1, 0xf); // Masks should be the same
        assertEq(mask2, 0xf);

        // Grant ROLE_A to user2 in RESOURCE_2
        access.grantRoles(RESOURCE_2, ROLE_A, user2);

        (counts1, mask1) = access.getAssigneeCount(RESOURCE_1, ROLE_A);
        (counts2, mask2) = access.getAssigneeCount(RESOURCE_2, ROLE_A);

        assertEq(counts1, 1); // RESOURCE_1 should still have 1
        assertEq(counts2, 1); // RESOURCE_2 has 1

        // Add more assignees to RESOURCE_1
        access.grantRoles(RESOURCE_1, ROLE_A, user2);
        access.grantRoles(RESOURCE_1, ROLE_A, superuser);

        (counts1, mask1) = access.getAssigneeCount(RESOURCE_1, ROLE_A);
        (counts2, mask2) = access.getAssigneeCount(RESOURCE_2, ROLE_A);

        assertEq(counts1, 3); // RESOURCE_1 should have 3 assignees
        assertEq(counts2, 1); // RESOURCE_2 should still have 1 assignee
    }

    function test_getAssigneeCount_with_root_resource() public {
        // Test getAssigneeCount with root resource

        // Grant ROLE_A in root resource
        access.grantRootRoles(ROLE_A, user1);

        (uint256 rootCounts, uint256 rootMask) = access.getAssigneeCount(
            access.ROOT_RESOURCE(),
            ROLE_A
        );
        (uint256 res1Counts, uint256 res1Mask) = access.getAssigneeCount(RESOURCE_1, ROLE_A);

        assertEq(rootCounts, 2); // Root resource should have 2 assignees (constructor + user1)
        assertEq(res1Counts, 0); // RESOURCE_1 should have 0 direct assignees
        assertEq(rootMask, 0xf);
        assertEq(res1Mask, 0xf);

        // Grant ROLE_A directly in RESOURCE_1
        access.grantRoles(RESOURCE_1, ROLE_A, user2);

        (rootCounts, rootMask) = access.getAssigneeCount(access.ROOT_RESOURCE(), ROLE_A);
        (res1Counts, res1Mask) = access.getAssigneeCount(RESOURCE_1, ROLE_A);

        assertEq(rootCounts, 2); // Root resource should still have 2 (constructor + user1)
        assertEq(res1Counts, 1); // RESOURCE_1 has 1 direct assignee

        // Note: Even though user1 has ROLE_A via root inheritance for RESOURCE_1,
        // getAssigneeCount only counts direct assignments to that resource
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1)); // user1 has the role via root
        assertEq(res1Counts, 1); // but only user2 is counted as direct assignee
    }

    function test_getAssigneeCount_consistency_with_hasAssignees() public {
        // Test that getAssigneeCount is consistent with hasAssignees

        uint256 roleBitmap = ROLE_A | ROLE_C;

        // Initially, no assignees
        (uint256 counts, ) = access.getAssigneeCount(RESOURCE_1, roleBitmap);
        bool hasAny = access.hasAssignees(RESOURCE_1, roleBitmap);

        assertEq(counts, 0);
        assertFalse(hasAny);

        // Grant ROLE_A only
        access.grantRoles(RESOURCE_1, ROLE_A, user1);

        (counts, ) = access.getAssigneeCount(RESOURCE_1, roleBitmap);
        hasAny = access.hasAssignees(RESOURCE_1, roleBitmap);

        assertEq(counts, 1); // Only ROLE_A has assignees
        assertTrue(hasAny); // hasAssignees should return true because at least one role has assignees

        // Grant ROLE_C as well
        access.grantRoles(RESOURCE_1, ROLE_C, user2);

        (counts, ) = access.getAssigneeCount(RESOURCE_1, roleBitmap);
        hasAny = access.hasAssignees(RESOURCE_1, roleBitmap);

        assertEq(counts, 0x101); // ROLE_A=1, ROLE_C=1
        assertTrue(hasAny);

        // Revoke ROLE_A
        access.revokeRoles(RESOURCE_1, ROLE_A, user1);

        (counts, ) = access.getAssigneeCount(RESOURCE_1, roleBitmap);
        hasAny = access.hasAssignees(RESOURCE_1, roleBitmap);

        assertEq(counts, 0x100); // ROLE_A=0, ROLE_C=1
        assertTrue(hasAny); // Still true because ROLE_C has assignees

        // Revoke ROLE_C
        access.revokeRoles(RESOURCE_1, ROLE_C, user2);

        (counts, ) = access.getAssigneeCount(RESOURCE_1, roleBitmap);
        hasAny = access.hasAssignees(RESOURCE_1, roleBitmap);

        assertEq(counts, 0);
        assertFalse(hasAny);
    }

    function test_getAssigneeCount_max_assignees() public {
        // Test getAssigneeCount with maximum assignees (15 per role)

        // Create 15 different user addresses
        address[] memory users = new address[](15);
        for (uint256 i = 0; i < 15; i++) {
            users[i] = makeAddr(string(abi.encodePacked("maxUser", i)));
        }

        // Grant ROLE_A to all 15 users
        for (uint256 i = 0; i < 15; i++) {
            access.grantRoles(RESOURCE_1, ROLE_A, users[i]);
        }

        (uint256 counts, uint256 mask) = access.getAssigneeCount(RESOURCE_1, ROLE_A);
        assertEq(counts, 15); // Should have exactly 15 assignees
        assertEq(mask, 0xf);

        // Test with multiple roles at max capacity
        for (uint256 i = 0; i < 15; i++) {
            access.grantRoles(RESOURCE_1, ROLE_D, users[i]);
        }

        (counts, mask) = access.getAssigneeCount(RESOURCE_1, ROLE_A | ROLE_D);
        assertEq(counts, 15 + 15 * 4096); // ROLE_A: 15*1, ROLE_D: 15*4096
        assertEq(mask, 61455);

        // Verify hasAssignees consistency
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_A));
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_D));
        assertTrue(access.hasAssignees(RESOURCE_1, ROLE_A | ROLE_D));
    }

    function test_getAssigneeCount_invalid_role_bitmap() public {
        // Test that getAssigneeCount rejects invalid role bitmaps

        uint256 invalidRoleA = ROLE_A | (1 << 1) | (1 << 2); // 0x7 = 0111 in first nybble
        uint256 invalidRoleB = ROLE_B | (1 << 5) | (1 << 6); // extra bits in second nybble

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACInvalidRoleBitmap.selector,
                invalidRoleA
            )
        );
        access.getAssigneeCount(RESOURCE_1, invalidRoleA);

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACInvalidRoleBitmap.selector,
                invalidRoleB
            )
        );
        access.getAssigneeCount(RESOURCE_1, invalidRoleB);

        // Valid bitmaps should still work
        access.grantRoles(RESOURCE_1, ROLE_A | ROLE_B, user1);
        (uint256 counts, uint256 mask) = access.getAssigneeCount(RESOURCE_1, ROLE_A | ROLE_B);
        assertEq(counts, 0x11); // Both roles should have 1 assignee
        assertEq(mask, 0xff); // Mask for first two nybbles
    }

    function test_getAssigneeCount_mask_calculation() public view {
        // Test that masks are calculated correctly for different role combinations

        // Single roles
        (, uint256 maskA) = access.getAssigneeCount(RESOURCE_1, ROLE_A);
        (, uint256 maskB) = access.getAssigneeCount(RESOURCE_1, ROLE_B);
        (, uint256 maskC) = access.getAssigneeCount(RESOURCE_1, ROLE_C);
        (, uint256 maskD) = access.getAssigneeCount(RESOURCE_1, ROLE_D);

        assertEq(maskA, 0xf); // First nybble
        assertEq(maskB, 0xf0); // Second nybble
        assertEq(maskC, 0xf00); // Third nybble
        assertEq(maskD, 0xf000); // Fourth nybble

        // Combined roles
        (, uint256 maskAB) = access.getAssigneeCount(RESOURCE_1, ROLE_A | ROLE_B);
        (, uint256 maskCD) = access.getAssigneeCount(RESOURCE_1, ROLE_C | ROLE_D);
        (, uint256 maskAC) = access.getAssigneeCount(RESOURCE_1, ROLE_A | ROLE_C);
        (, uint256 maskBD) = access.getAssigneeCount(RESOURCE_1, ROLE_B | ROLE_D);
        (, uint256 maskAll) = access.getAssigneeCount(
            RESOURCE_1,
            ROLE_A | ROLE_B | ROLE_C | ROLE_D
        );

        assertEq(maskAB, 0xff); // First two nybbles
        assertEq(maskCD, 0xff00); // Last two nybbles
        assertEq(maskAC, 0xf0f); // First and third nybbles
        assertEq(maskBD, 0xf0f0); // Second and fourth nybbles
        assertEq(maskAll, 0xffff); // All four nybbles
    }

    function test_getAssigneeCount_zero_bitmap() public view {
        // Test getAssigneeCount with zero role bitmap - should return zero counts
        (uint256 counts, uint256 mask) = access.getAssigneeCount(RESOURCE_1, 0);
        assertEq(counts, 0);
        assertEq(mask, 0);
    }

    // Tests for admin role restrictions

    function test_grantRoles_rejects_admin_roles() public {
        // Test that grantRoles reverts when trying to grant admin roles
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACCannotGrantRoles.selector,
                RESOURCE_1,
                ADMIN_ROLE_A,
                admin
            )
        );
        access.grantRoles(RESOURCE_1, ADMIN_ROLE_A, user1);

        // Test with a mix of regular and admin roles
        uint256 mixedRoles = ROLE_A | ADMIN_ROLE_A;
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACCannotGrantRoles.selector,
                RESOURCE_1,
                mixedRoles,
                admin
            )
        );
        access.grantRoles(RESOURCE_1, mixedRoles, user1);

        // Test with multiple admin roles
        uint256 multipleAdminRoles = ADMIN_ROLE_A | ADMIN_ROLE_B;
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACCannotGrantRoles.selector,
                RESOURCE_1,
                multipleAdminRoles,
                admin
            )
        );
        access.grantRoles(RESOURCE_1, multipleAdminRoles, user1);

        // Test that regular roles still work
        access.grantRoles(RESOURCE_1, ROLE_A | ROLE_B, user1);
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B, user1));
    }

    function test_canRevokeRoles_allows_admin_roles() public {
        // First grant some roles (including admin roles via direct method)
        access.grantRoles(RESOURCE_1, ROLE_A, user1);
        access.grantRolesDirect(RESOURCE_1, ADMIN_ROLE_A, user1);

        // Verify roles were granted
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertTrue(access.hasRoles(RESOURCE_1, ADMIN_ROLE_A, user1));

        vm.recordLogs();

        // Test that revokeRoles can now revoke admin roles
        access.revokeRoles(RESOURCE_1, ADMIN_ROLE_A, user1);
        assertFalse(access.hasRoles(RESOURCE_1, ADMIN_ROLE_A, user1));

        // Verify event was emitted correctly
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EACRolesRevoked(uint256,uint256,address)"));
        (uint256 resource, uint256 roles, address account) = abi.decode(
            entries[0].data,
            (uint256, uint256, address)
        );
        assertEq(resource, RESOURCE_1);
        assertEq(roles, ADMIN_ROLE_A);
        assertEq(account, user1);

        // Grant both admin roles and test revoking multiple admin roles
        access.grantRolesDirect(RESOURCE_1, ADMIN_ROLE_A | ADMIN_ROLE_B, user1);
        uint256 multipleAdminRoles = ADMIN_ROLE_A | ADMIN_ROLE_B;

        vm.recordLogs();
        access.revokeRoles(RESOURCE_1, multipleAdminRoles, user1);
        assertFalse(access.hasRoles(RESOURCE_1, ADMIN_ROLE_A | ADMIN_ROLE_B, user1));

        // Verify event was emitted correctly for multiple admin roles
        entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        (resource, roles, account) = abi.decode(entries[0].data, (uint256, uint256, address));
        assertEq(resource, RESOURCE_1);
        assertEq(roles, multipleAdminRoles);
        assertEq(account, user1);

        // Test that regular roles can still be revoked
        access.revokeRoles(RESOURCE_1, ROLE_A, user1);
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A, user1));
    }

    function test_grantRootRoles_rejects_admin_roles() public {
        // Test that grantRootRoles rejects admin roles
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACCannotGrantRoles.selector,
                access.ROOT_RESOURCE(),
                ADMIN_ROLE_A | ADMIN_ROLE_B,
                admin
            )
        );
        access.grantRootRoles(ADMIN_ROLE_A | ADMIN_ROLE_B, user1);

        // Test single admin role rejection
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACCannotGrantRoles.selector,
                access.ROOT_RESOURCE(),
                ADMIN_ROLE_A,
                admin
            )
        );
        access.grantRootRoles(ADMIN_ROLE_A, user1);

        // Test that regular roles still work
        access.grantRootRoles(ROLE_A | ROLE_B, user1);
        assertTrue(access.hasRootRoles(ROLE_A | ROLE_B, user1));
    }

    function test_canRevokeRoles_allows_root_admin_roles() public {
        // First grant regular roles via grantRootRoles and admin roles via direct method
        access.grantRootRoles(ROLE_A | ROLE_B, user1);
        access.grantRolesDirect(access.ROOT_RESOURCE(), ADMIN_ROLE_A | ADMIN_ROLE_B, user1);

        assertTrue(access.hasRootRoles(ROLE_A | ROLE_B, user1));
        assertTrue(access.hasRootRoles(ADMIN_ROLE_A | ADMIN_ROLE_B, user1));

        vm.recordLogs();

        // Test that revokeRootRoles can now revoke admin roles
        access.revokeRootRoles(ADMIN_ROLE_A, user1);
        assertFalse(access.hasRootRoles(ADMIN_ROLE_A, user1));
        assertTrue(access.hasRootRoles(ADMIN_ROLE_B, user1)); // Other admin role should remain

        // Verify event was emitted correctly
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EACRolesRevoked(uint256,uint256,address)"));
        (uint256 resource, uint256 roles, address account) = abi.decode(
            entries[0].data,
            (uint256, uint256, address)
        );
        assertEq(resource, access.ROOT_RESOURCE());
        assertEq(roles, ADMIN_ROLE_A);
        assertEq(account, user1);

        // Test revoking multiple admin roles
        vm.recordLogs();
        access.revokeRootRoles(ADMIN_ROLE_B, user1);
        assertFalse(access.hasRootRoles(ADMIN_ROLE_B, user1));

        entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        (resource, roles, account) = abi.decode(entries[0].data, (uint256, uint256, address));
        assertEq(resource, access.ROOT_RESOURCE());
        assertEq(roles, ADMIN_ROLE_B);
        assertEq(account, user1);

        // Test that regular roles can still be revoked
        access.revokeRootRoles(ROLE_A, user1);
        assertFalse(access.hasRootRoles(ROLE_A, user1));
        assertTrue(access.hasRootRoles(ROLE_B, user1));
    }

    function test_canRevokeRoles_unauthorized() public {
        // Grant roles to user2
        access.grantRoles(RESOURCE_1, ROLE_A, user2);
        access.grantRolesDirect(RESOURCE_1, ADMIN_ROLE_A, user2);

        // Verify user2 has the roles
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user2));
        assertTrue(access.hasRoles(RESOURCE_1, ADMIN_ROLE_A, user2));

        // user1 attempts to revoke roles from user2 but doesn't have admin privileges
        vm.startPrank(user1);

        // Should revert with EACCannotRevokeRoles for regular roles
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACCannotRevokeRoles.selector,
                RESOURCE_1,
                ROLE_A,
                user1
            )
        );
        access.revokeRoles(RESOURCE_1, ROLE_A, user2);

        // Should revert with EACCannotRevokeRoles for admin roles
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACCannotRevokeRoles.selector,
                RESOURCE_1,
                ADMIN_ROLE_A,
                user1
            )
        );
        access.revokeRoles(RESOURCE_1, ADMIN_ROLE_A, user2);

        vm.stopPrank();

        // Verify user2 still has the roles (they weren't revoked)
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user2));
        assertTrue(access.hasRoles(RESOURCE_1, ADMIN_ROLE_A, user2));
    }

    function test_canRevokeRoles_mixed_roles() public {
        // Grant regular and admin roles to user1
        access.grantRoles(RESOURCE_1, ROLE_A | ROLE_B, user1);
        access.grantRolesDirect(RESOURCE_1, ADMIN_ROLE_A | ADMIN_ROLE_B, user1);

        // Verify roles were granted
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B, user1));
        assertTrue(access.hasRoles(RESOURCE_1, ADMIN_ROLE_A | ADMIN_ROLE_B, user1));

        vm.recordLogs();

        // Test revoking a mix of regular and admin roles
        uint256 mixedRoles = ROLE_A | ADMIN_ROLE_A;
        access.revokeRoles(RESOURCE_1, mixedRoles, user1);

        // Verify both regular and admin roles were revoked
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ADMIN_ROLE_A, user1));

        // Verify other roles remain
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_B, user1));
        assertTrue(access.hasRoles(RESOURCE_1, ADMIN_ROLE_B, user1));

        // Verify event was emitted correctly
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EACRolesRevoked(uint256,uint256,address)"));
        (uint256 resource, uint256 roles, address account) = abi.decode(
            entries[0].data,
            (uint256, uint256, address)
        );
        assertEq(resource, RESOURCE_1);
        assertEq(roles, mixedRoles);
        assertEq(account, user1);
    }

    function test_canRevokeRoles_with_root_admin_privileges() public {
        // Grant admin role in ROOT_RESOURCE to user1
        access.grantRolesDirect(access.ROOT_RESOURCE(), ADMIN_ROLE_A, user1);

        // Grant roles to user2
        access.grantRoles(RESOURCE_1, ROLE_A, user2);
        access.grantRolesDirect(RESOURCE_1, ADMIN_ROLE_A, user2);

        // Verify initial state
        assertTrue(access.hasRootRoles(ADMIN_ROLE_A, user1));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ADMIN_ROLE_A, user2));

        // user1 should be able to revoke roles from user2 using root admin privileges
        vm.startPrank(user1);

        // Revoke regular role
        access.revokeRoles(RESOURCE_1, ROLE_A, user2);
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A, user2));

        // Revoke admin role
        access.revokeRoles(RESOURCE_1, ADMIN_ROLE_A, user2);
        assertFalse(access.hasRoles(RESOURCE_1, ADMIN_ROLE_A, user2));

        vm.stopPrank();
    }
}
