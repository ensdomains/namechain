// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {EnhancedAccessControl} from "../src/registry/EnhancedAccessControl.sol";

contract MockEnhancedAccessControl is EnhancedAccessControl {
    constructor() EnhancedAccessControl(msg.sender) {
    }

    function setRoleAdmin(uint256 roles, uint256 adminRoleId) external {
        _setRoleAdmin(roles, adminRoleId);
    }
    
    function callOnlyRootRole(uint256 roles) external onlyRootRole(roles) {
        // Function that will revert if caller doesn't have the role in root resource
    }

    function copyRoles(bytes32 resource, address srcAccount, address dstAccount) external {
        _copyRoles(resource, srcAccount, dstAccount);
    }

    function revokeAllRoles(bytes32 resource, address account) external returns (bool) {
        return _revokeAllRoles(resource, account);
    }
    
    function grantRoles(bytes32 resource, uint256 roleBitmap, address account) external returns (bool) {
        return _grantRoles(resource, roleBitmap, account);
    }
    
    function lockRoles(bytes32 resource, uint256 roleBitmap) external {
        _lockRoles(resource, roleBitmap);
    }
}

contract EnhancedAccessControlTest is Test {
    uint256 public constant ROLE_A = 1 << 1;
    uint256 public constant ROLE_B = 1 << 2;
    uint256 public constant ROLE_C = 1 << 3;
    uint256 public constant ROLE_D = 1 << 4;
    bytes32 public constant RESOURCE_1 = bytes32(keccak256("RESOURCE_1"));
    bytes32 public constant RESOURCE_2 = bytes32(keccak256("RESOURCE_2"));

    MockEnhancedAccessControl access;
    address admin;
    address user1;
    address user2;

    function setUp() public {
        admin = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        access = new MockEnhancedAccessControl();
    }

    function test_initial_admin_role() public view {
        assertTrue(access.hasRoles(RESOURCE_1, access.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(access.hasRoles(RESOURCE_2, access.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_grant_roles() public {
        vm.recordLogs();
        
        // Create a bitmap with roles ROLE_A, ROLE_B, and ROLE_C
        uint256 roleBitmap = ROLE_A | ROLE_B | ROLE_C;
        
        access.grantRoles(RESOURCE_1, roleBitmap, user1);
        
        // Verify all roles were granted
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_B, user1));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_C, user1));
        
        // Verify roles were not granted for other resources
        assertFalse(access.hasRoles(RESOURCE_2, ROLE_A, user1));
        assertFalse(access.hasRoles(RESOURCE_2, ROLE_B, user1));
        assertFalse(access.hasRoles(RESOURCE_2, ROLE_C, user1));

        // Verify events were emitted
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        
        assertEq(entries[0].topics[0], keccak256("EACRolesGranted(bytes32,uint256,address,address)"));
        (bytes32 resource, uint256 emittedRoleBitmap, address account, address sender) = abi.decode(entries[0].data, (bytes32, uint256, address, address));
        assertEq(resource, RESOURCE_1);
        assertEq(emittedRoleBitmap, roleBitmap);
        assertEq(account, user1);
        assertEq(sender, address(this));
        
        // Test granting roles that are already granted (should not emit events)
        vm.recordLogs();
        access.grantRoles(RESOURCE_1, roleBitmap, user1);
        entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
        
        // Test granting a mix of new and existing roles
        vm.recordLogs();
        uint256 mixedRoleBitmap = ROLE_A | ROLE_D; // ROLE_A already granted, ROLE_D is new
        
        access.grantRoles(RESOURCE_1, mixedRoleBitmap, user1);
        
        entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        (bytes32 resource2, uint256 emittedRoleBitmap2, address account2, address sender2) = abi.decode(entries[0].data, (bytes32, uint256, address, address));
        assertEq(resource2, RESOURCE_1);
        assertEq(emittedRoleBitmap2, mixedRoleBitmap);
        assertEq(account2, user1);
        assertEq(sender2, address(this));
    }

    function test_has_root_role() public {
        // Initially user1 doesn't have the role in root resource
        assertFalse(access.hasRootRoles(ROLE_A, user1));
        
        // Grant role in root resource
        access.grantRole(access.ROOT_RESOURCE(), ROLE_A, user1);
        
        // Now user1 should have the role in root resource
        assertTrue(access.hasRootRoles(ROLE_A, user1));
        
        // Revoking the role should remove it
        access.revokeRole(access.ROOT_RESOURCE(), ROLE_A, user1);
        assertFalse(access.hasRootRoles(ROLE_A, user1));
        
        // Having a role in a specific resource doesn't mean having it in root resource
        access.grantRole(RESOURCE_1, ROLE_A, user1);
        assertFalse(access.hasRootRoles(ROLE_A, user1));
    }

    function test_only_root_role() public {
        // Grant role in root resource to user1
        access.grantRole(access.ROOT_RESOURCE(), ROLE_A, user1);
        
        // User1 should be able to call function with onlyRootRole modifier
        vm.prank(user1);
        access.callOnlyRootRole(ROLE_A);
        
        // User2 doesn't have the role, should revert
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRole.selector, access.ROOT_RESOURCE(), ROLE_A, user2));
        vm.prank(user2);
        access.callOnlyRootRole(ROLE_A);
        
        // Having the role in a specific resource doesn't satisfy onlyRootRole
        access.grantRole(RESOURCE_1, ROLE_A, user2);
        
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRole.selector, access.ROOT_RESOURCE(), ROLE_A, user2));
        vm.prank(user2);
        access.callOnlyRootRole(ROLE_A);
    }

    function test_grant_role_return_value() public {
        bool success = access.grantRole(RESOURCE_1, ROLE_A, user1);
        assertTrue(success);

        // Granting an already granted role should return false
        success = access.grantRole(RESOURCE_1, ROLE_A, user1);
        assertFalse(success);
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));
    }

    function test_revoke_role() public {
        access.grantRole(RESOURCE_1, ROLE_A, user1);
        
        vm.recordLogs();
        access.revokeRole(RESOURCE_1, ROLE_A, user1);
        
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A, user1));

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EACRolesRevoked(bytes32,uint256,address,address)"));
        (bytes32 resource, uint256 roles, address account, address sender) = abi.decode(entries[0].data, (bytes32, uint256, address, address));
        assertEq(resource, RESOURCE_1);
        assertEq(roles, ROLE_A);
        assertEq(account, user1);
        assertEq(sender, address(this));
    }

    function test_renounce_role() public {
        // First grant the role to user1
        access.grantRole(RESOURCE_1, ROLE_A, user1);
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        
        vm.startPrank(user1);
        bool success = access.renounceRole(RESOURCE_1, ROLE_A, user1);
        assertTrue(success);
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        vm.stopPrank();
    }

    function test_renounce_role_returns_false_when_no_role() public {
        // Ensure user1 doesn't have the role
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        
        vm.startPrank(user1);
        bool success = access.renounceRole(RESOURCE_1, ROLE_A, user1);
        assertFalse(success);
        vm.stopPrank();
    }

    function test_set_role_admin() public {
        vm.recordLogs();
        access.setRoleAdmin(ROLE_A, ROLE_B);
        
        assertEq(access.getRoleAdmin(ROLE_A), ROLE_B);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EACRoleAdminChanged(uint256,uint256,uint256)"));
        (uint256 roles, uint256 previousAdmin, uint256 newAdmin) = abi.decode(entries[0].data, (uint256, uint256, uint256));
        assertEq(roles, ROLE_A);
        assertEq(previousAdmin, 0);
        assertEq(newAdmin, ROLE_B);

        access.grantRole(RESOURCE_1, ROLE_B, user1);

        vm.prank(user1);
        access.grantRole(RESOURCE_1, ROLE_A, user2);
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user2));

        vm.prank(user1);
        access.revokeRole(RESOURCE_1, ROLE_A, user2);
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A, user2));
    }

    function test_Revert_unauthorized_grant() public {
        // Set ROLE_B as the admin role for ROLE_A
        access.setRoleAdmin(ROLE_A, ROLE_B);
        
        // Now user1 doesn't have ROLE_B, so this should revert
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountAdminRole.selector, RESOURCE_1, ROLE_A, user1));
        vm.prank(user1);
        access.grantRole(RESOURCE_1, ROLE_A, user2);
    }

    function test_Revert_unauthorized_revoke() public {
        // Set ROLE_B as the admin role for ROLE_A
        access.setRoleAdmin(ROLE_A, ROLE_B);
        
        access.grantRole(RESOURCE_1, ROLE_A, user2);
        
        // Now user1 doesn't have ROLE_B, so this should revert
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountAdminRole.selector, RESOURCE_1, ROLE_A, user1));
        vm.prank(user1);
        access.revokeRole(RESOURCE_1, ROLE_A, user2);
    }

    function test_Revert_bad_renounce_confirmation() public {
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACBadConfirmation.selector));
        vm.prank(user1);
        access.renounceRole(RESOURCE_1, ROLE_A, user2);
    }

    function test_role_isolation() public {
        access.grantRole(RESOURCE_1, ROLE_A, user1);
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertFalse(access.hasRoles(RESOURCE_2, ROLE_A, user1));
    }

    function test_supports_interface() public view {
        assertTrue(access.supportsInterface(type(EnhancedAccessControl).interfaceId));
    }

    function test_root_resource_role_applies_to_all_resources() public {
        access.grantRole(access.ROOT_RESOURCE(), ROLE_A, user1);
        
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertTrue(access.hasRoles(RESOURCE_2, ROLE_A, user1));
        assertTrue(access.hasRoles(bytes32(keccak256("ANY_OTHER_RESOURCE")), ROLE_A, user1));
    }

    function test_copy_roles() public {
        // Setup: Grant multiple roles to user1
        access.grantRole(RESOURCE_1, ROLE_A, user1);
        access.grantRole(RESOURCE_1, ROLE_B, user1);
        access.grantRole(RESOURCE_2, ROLE_A, user1);
        
        // Verify initial state
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_B, user1));
        assertTrue(access.hasRoles(RESOURCE_2, ROLE_A, user1));
        
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A, user2));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_B, user2));
        assertFalse(access.hasRoles(RESOURCE_2, ROLE_A, user2));
        
        // Record logs to verify event emission
        vm.recordLogs();
        
        // Copy roles from user1 to user2 for RESOURCE_1
        access.copyRoles(RESOURCE_1, user1, user2);
        
        // Verify roles were copied correctly for RESOURCE_1
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user2));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_B, user2));
        
        // Verify roles for RESOURCE_2 were not copied
        assertFalse(access.hasRoles(RESOURCE_2, ROLE_A, user2));
        
        // Verify user1 still has all original roles
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_B, user1));
        assertTrue(access.hasRoles(RESOURCE_2, ROLE_A, user1));
        
        // Verify event was emitted correctly
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EACRolesCopied(bytes32,bytes32,address,address,uint256)"));
        (bytes32 srcResource, bytes32 dstResource, address srcAccount, address dstAccount, uint256 roleBitmap) = abi.decode(entries[0].data, (bytes32, bytes32, address, address, uint256));
        assertEq(srcResource, RESOURCE_1);
        assertEq(dstResource, RESOURCE_1);
        assertEq(srcAccount, user1);
        assertEq(dstAccount, user2);
        // The bitmap should have bits set for ROLE_A and ROLE_B
        assertEq(roleBitmap, ROLE_A | ROLE_B);
    }


    function test_revoke_all_roles() public {
        // Setup: Grant multiple roles to user1
        access.grantRole(RESOURCE_1, ROLE_A, user1);
        access.grantRole(RESOURCE_1, ROLE_B, user1);
        access.grantRole(RESOURCE_2, ROLE_A, user1);
        
        // Verify initial state
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_B, user1));
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
        assertEq(entries[0].topics[0], keccak256("EACRolesRevoked(bytes32,uint256,address,address)"));
        (bytes32 resource, uint256 roles, address account, address sender) = abi.decode(entries[0].data, (bytes32, uint256, address, address));
        assertEq(resource, RESOURCE_1);
        assertEq(roles, ROLE_A | ROLE_B);
        assertEq(account, user1);
        assertEq(sender, address(this));
        
        // Test revoking all roles when there are no roles to revoke
        vm.recordLogs();
        success = access.revokeAllRoles(RESOURCE_1, user1);
        
        // Verify the operation was not successful (no roles to revoke)
        assertFalse(success);
        
        // Verify no event was emitted
        entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
    }

    function test_copy_roles_bitwise_or() public {
        // Setup: Grant different roles to user1 and user2
        access.grantRole(RESOURCE_1, ROLE_A, user1);
        access.grantRole(RESOURCE_1, ROLE_B, user1);
        access.grantRole(RESOURCE_1, ROLE_C, user2);
        access.grantRole(RESOURCE_1, ROLE_D, user2);
        
        // Verify initial state
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_B, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_C, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_D, user1));
        
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_C, user2));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_D, user2));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A, user2));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_B, user2));
        
        // Record logs to verify event emission
        vm.recordLogs();

        // Copy roles from user1 to user2 for RESOURCE_1
        // This should OR the roles, not overwrite them
        access.copyRoles(RESOURCE_1, user1, user2);
        
        // Verify user2 now has all roles (original + copied)
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user2));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_B, user2));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_C, user2));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_D, user2));
        
        // Verify event was emitted correctly with the correct bitmap
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EACRolesCopied(bytes32,bytes32,address,address,uint256)"));
        (bytes32 srcResource, bytes32 dstResource, address srcAccount, address dstAccount, uint256 roleBitmap) = abi.decode(entries[0].data, (bytes32, bytes32, address, address, uint256));
        assertEq(srcResource, RESOURCE_1);
        assertEq(dstResource, RESOURCE_1);
        assertEq(srcAccount, user1);
        assertEq(dstAccount, user2);
        assertEq(roleBitmap, ROLE_A | ROLE_B);
    }

    function test_lock_roles() public {
        // Initially no roles are locked
        assertEq(access.getLockedRoles(RESOURCE_1), 0);
        
        // Record logs to verify event emission
        vm.recordLogs();
        
        // Lock ROLE_A
        access.lockRoles(RESOURCE_1, ROLE_A);
        
        // Verify ROLE_A is now locked
        assertEq(access.getLockedRoles(RESOURCE_1), ROLE_A);
        
        // Verify event was emitted correctly
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EACRolesLocked(bytes32,uint256)"));
        (bytes32 resource, uint256 roleBitmap) = abi.decode(entries[0].data, (bytes32, uint256));
        assertEq(resource, RESOURCE_1);
        assertEq(roleBitmap, ROLE_A);
        
        // Lock additional roles
        vm.recordLogs();
        access.lockRoles(RESOURCE_1, ROLE_B | ROLE_C);
        
        // Verify roles are now locked (should be a bitwise OR with existing locks)
        assertEq(access.getLockedRoles(RESOURCE_1), ROLE_A | ROLE_B | ROLE_C);
        
        // Verify event was emitted correctly for the additional locks
        entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EACRolesLocked(bytes32,uint256)"));
        (resource, roleBitmap) = abi.decode(entries[0].data, (bytes32, uint256));
        assertEq(resource, RESOURCE_1);
        assertEq(roleBitmap, ROLE_B | ROLE_C);
        
        // Verify locks are resource-specific
        assertEq(access.getLockedRoles(RESOURCE_2), 0);
        
        // Lock roles in a different resource
        access.lockRoles(RESOURCE_2, ROLE_D);
        assertEq(access.getLockedRoles(RESOURCE_2), ROLE_D);
    }
    
    function test_Revert_revoke_locked_role() public {
        // Grant role to user1
        access.grantRole(RESOURCE_1, ROLE_A, user1);
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        
        // Lock the role
        access.lockRoles(RESOURCE_1, ROLE_A);
        
        // Attempt to revoke the locked role should revert
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACLockedRole.selector, RESOURCE_1, ROLE_A));
        access.revokeRole(RESOURCE_1, ROLE_A, user1);
        
        // Verify role was not revoked
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        
        // Grant another role that's not locked
        access.grantRole(RESOURCE_1, ROLE_B, user1);
        
        // Should be able to revoke the non-locked role
        access.revokeRole(RESOURCE_1, ROLE_B, user1);
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_B, user1));
    }
    
    function test_Revert_renounce_locked_role() public {
        // Grant role to user1
        access.grantRole(RESOURCE_1, ROLE_A, user1);
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        
        // Lock the role
        access.lockRoles(RESOURCE_1, ROLE_A);
        
        // Attempt to renounce the locked role should revert
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACLockedRole.selector, RESOURCE_1, ROLE_A));
        access.renounceRole(RESOURCE_1, ROLE_A, user1);
        
        // Verify role was not renounced
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));
    }
    
    function test_Revert_revoke_all_with_locked_roles() public {
        // Grant multiple roles to user1
        access.grantRole(RESOURCE_1, ROLE_A, user1);
        access.grantRole(RESOURCE_1, ROLE_B, user1);
        
        // Lock one of the roles
        access.lockRoles(RESOURCE_1, ROLE_A);
        
        // Attempt to revoke all roles should revert because one is locked
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACLockedRole.selector, RESOURCE_1, ROLE_A));
        access.revokeAllRoles(RESOURCE_1, user1);
        
        // Verify no roles were revoked
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_B, user1));
    }
    
    function test_revoke_all_with_no_locked_roles() public {
        // Grant multiple roles to user1
        access.grantRole(RESOURCE_1, ROLE_A, user1);
        access.grantRole(RESOURCE_1, ROLE_B, user1);
        
        // Lock roles in a different resource
        access.lockRoles(RESOURCE_2, ROLE_A | ROLE_B);
        
        // Should be able to revoke all roles in RESOURCE_1 since none are locked there
        bool success = access.revokeAllRoles(RESOURCE_1, user1);
        assertTrue(success);
        
        // Verify all roles were revoked
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_B, user1));
    }
    
    function test_partial_revoke_with_locked_roles() public {
        // Grant multiple roles to user1
        access.grantRole(RESOURCE_1, ROLE_A, user1);
        access.grantRole(RESOURCE_1, ROLE_B, user1);
        access.grantRole(RESOURCE_1, ROLE_C, user1);
        
        // Lock one of the roles
        access.lockRoles(RESOURCE_1, ROLE_B);
        
        // Should be able to revoke non-locked roles individually
        access.revokeRole(RESOURCE_1, ROLE_A, user1);
        access.revokeRole(RESOURCE_1, ROLE_C, user1);
        
        // Verify only the locked role remains
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_B, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_C, user1));
        
        // Attempt to revoke multiple roles including a locked one should revert
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACLockedRole.selector, RESOURCE_1, ROLE_B));
        access.revokeRole(RESOURCE_1, ROLE_A | ROLE_B, user1);
    }
    
    function test_has_roles_requires_all_roles() public {
        // Grant only ROLE_A and ROLE_B to user1
        access.grantRole(RESOURCE_1, ROLE_A | ROLE_B, user1);
        
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
        access.grantRole(RESOURCE_1, ROLE_C, user1);
        
        // Now combinations with A, B, C should work, but not with D
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B | ROLE_C, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B | ROLE_C | ROLE_D, user1));
    }
    
    function test_has_root_roles_requires_all_roles() public {
        // Grant only ROLE_A and ROLE_B to user1 in root resource
        access.grantRole(access.ROOT_RESOURCE(), ROLE_A | ROLE_B, user1);
        
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
        access.grantRole(access.ROOT_RESOURCE(), ROLE_C, user1);
        
        // Now combinations with A, B, C should work, but not with D
        assertTrue(access.hasRootRoles(ROLE_A | ROLE_B | ROLE_C, user1));
        assertFalse(access.hasRootRoles(ROLE_A | ROLE_B | ROLE_C | ROLE_D, user1));
    }
} 