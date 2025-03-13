// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {EnhancedAccessControl} from "../src/registry/EnhancedAccessControl.sol";

abstract contract MockRoles {
    bytes32 public constant RESOURCE_1 = bytes32(keccak256("RESOURCE_1"));
    bytes32 public constant RESOURCE_2 = bytes32(keccak256("RESOURCE_2"));

    uint256 public constant ROLE_A = 1 << 0;
    uint256 public constant ROLE_B = 1 << 1;
    uint256 public constant ROLE_C = 1 << 2;
    uint256 public constant ROLE_D = 1 << 3;
    uint256 public constant ADMIN_ROLE = 1 << 128;
    uint256 public constant ADMIN_ROLE_2 = 1 << 129;
    uint256 public constant ADMIN_ROLE_3 = 1 << 130;
    
}

contract MockEnhancedAccessControl is EnhancedAccessControl, MockRoles {
    constructor() {
        // Self-grant role access in the root resource
        _grantRoles(ROOT_RESOURCE, ROLE_A | ROLE_B | ROLE_C | ADMIN_ROLE | ADMIN_ROLE_2 | ADMIN_ROLE_3, msg.sender);
    }
    
    function callOnlyRootRoles(uint256 roleBitmap) external onlyRootRoles(roleBitmap) {
        // Function that will revert if caller doesn't have the roles in root resource
    }

    function copyRoles(bytes32 resource, address srcAccount, address dstAccount) external {
        _copyRoles(resource, srcAccount, dstAccount);
    }

    function revokeAllRoles(bytes32 resource, address account) external returns (bool) {
        return _revokeAllRoles(resource, account);
    }
}

contract EnhancedAccessControlTest is Test, MockRoles {
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

    function test_initial_roles() public view {
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B | ROLE_C | ADMIN_ROLE, admin));
    }

    function test_grant_roles() public {
        vm.recordLogs();
        
        // Create a bitmap with roles ROLE_A, ROLE_B, with ADMIN_ROLE as the admin
        uint256 roleBitmap = ROLE_A | ROLE_B | ADMIN_ROLE;
        
        access.grantRoles(RESOURCE_1, roleBitmap, user1);
        
        // Verify all roles were granted
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B | ADMIN_ROLE, user1));
        
        // Verify roles were not granted for other resources
        assertFalse(access.hasRoles(RESOURCE_2, ROLE_A, user1));
        assertFalse(access.hasRoles(RESOURCE_2, ROLE_B, user1));
        assertFalse(access.hasRoles(RESOURCE_2, ADMIN_ROLE, user1));

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
        uint256 mixedRoleBitmap = ROLE_C | ADMIN_ROLE;
        
        access.grantRoles(RESOURCE_1, mixedRoleBitmap, user1);
        
        entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        (bytes32 resource2, uint256 emittedRoleBitmap2, address account2, address sender2) = abi.decode(entries[0].data, (bytes32, uint256, address, address));
        assertEq(resource2, RESOURCE_1);
        assertEq(emittedRoleBitmap2, mixedRoleBitmap);
        assertEq(account2, user1);
        assertEq(sender2, address(this));
    }

    // Test that unauthorized accounts cannot grant roles
    function test_grant_roles_unauthorizedAdmin() public {
        // Create a bitmap with roles ROLE_A with ADMIN_ROLE as the admin
        uint256 roleBitmap = ROLE_A | ADMIN_ROLE;
        
        // Grant ROLE_A (but not ADMIN_ROLE) to user1
        access.grantRoles(RESOURCE_1, roleBitmap, user1);
        
        // Verify user1 has the roles
        assertTrue(access.hasRoles(RESOURCE_1, roleBitmap, user1));
        
        // user1 attempts to grant ROLE_B which requires ADMIN_ROLE admin
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountAdminRoles.selector, RESOURCE_1, ROLE_B, user1));
        access.grantRoles(RESOURCE_1, ROLE_B, user2);
    }

    function test_grant_roles_return_value() public {
        uint256 roleBitmap = ROLE_A | ADMIN_ROLE;
        
        bool success = access.grantRoles(RESOURCE_1, roleBitmap, user1);
        assertTrue(success);

        // Granting an already granted role should return false
        success = access.grantRoles(RESOURCE_1, roleBitmap, user1);
        assertFalse(success);
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));
    }

    function test_has_root_roles() public {
        // Initially user1 doesn't have the role in root resource
        assertFalse(access.hasRootRoles(ROLE_A, user1));
        
        // Grant role in root resource using ADMIN_ROLE as admin
        access.grantRoles(access.ROOT_RESOURCE(), ROLE_A | ADMIN_ROLE, user1);
        
        // Now user1 should have the role in root resource
        assertTrue(access.hasRootRoles(ROLE_A | ADMIN_ROLE, user1));
        
        // Revoking the role should remove it
        access.revokeRoles(access.ROOT_RESOURCE(), ROLE_A | ADMIN_ROLE, user1);
        assertFalse(access.hasRootRoles(ROLE_A | ADMIN_ROLE, user1));
        
        // Having a role in a specific resource doesn't mean having it in root resource
        access.grantRoles(RESOURCE_1, ROLE_A | ADMIN_ROLE, user1);
        assertFalse(access.hasRootRoles(ROLE_A | ADMIN_ROLE, user1));
    }

    function test_only_root_roles() public {
        // Grant role in root resource to user1
        access.grantRoles(access.ROOT_RESOURCE(), ROLE_A | ADMIN_ROLE, user1);
        
        // User1 should be able to call function with onlyRootRoles modifier
        vm.prank(user1);
        access.callOnlyRootRoles(ROLE_A);
        
        // User2 doesn't have the role, should revert
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, access.ROOT_RESOURCE(), ROLE_A, user2));
        vm.prank(user2);
        access.callOnlyRootRoles(ROLE_A);
        
        // Having the role in a specific resource doesn't satisfy onlyRootRoles
        access.grantRoles(RESOURCE_1, ROLE_A | ADMIN_ROLE, user2);   
        
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, access.ROOT_RESOURCE(), ROLE_A, user2));
        vm.prank(user2);
        access.callOnlyRootRoles(ROLE_A);
    }

    function test_has_roles_requires_all_roles() public {
        // Grant only ROLE_A and ROLE_B to user1
        access.grantRoles(RESOURCE_1, ROLE_A | ROLE_B | ADMIN_ROLE, user1);
        
        // Verify individual roles work
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_B, user1));
        assertTrue(access.hasRoles(RESOURCE_1, ADMIN_ROLE, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_C, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_D, user1));
        
        // Verify combinations with only granted roles work
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B | ADMIN_ROLE, user1));
        
        // Verify combinations with at least one missing role fail
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_C, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_B | ROLE_D, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B | ROLE_C, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B | ROLE_C | ROLE_D, user1));
        
        // Grant one more role and test again
        access.grantRoles(RESOURCE_1, ROLE_C | ROLE_D | ADMIN_ROLE, user1);
        
        // Now combinations with A, B, C and D should work
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B | ROLE_C | ROLE_D | ADMIN_ROLE, user1));
    }
    
    function test_has_root_roles_requires_all_roles() public {
        // Grant only ROLE_A and ROLE_B to user1 in root resource
        access.grantRoles(access.ROOT_RESOURCE(), ROLE_A | ROLE_B | ADMIN_ROLE, user1);
        
        // Verify individual roles work
        assertTrue(access.hasRootRoles(ROLE_A, user1));
        assertTrue(access.hasRootRoles(ROLE_B, user1));
        assertTrue(access.hasRootRoles(ADMIN_ROLE, user1));
        assertFalse(access.hasRootRoles(ROLE_C, user1));
        assertFalse(access.hasRootRoles(ROLE_D, user1));
        
        // Verify combinations with only granted roles work
        assertTrue(access.hasRootRoles(ROLE_A | ROLE_B | ADMIN_ROLE, user1));
        
        // Verify combinations with at least one missing role fail
        assertFalse(access.hasRootRoles(ROLE_A | ROLE_C, user1));
        assertFalse(access.hasRootRoles(ROLE_B | ROLE_D, user1));
        assertFalse(access.hasRootRoles(ROLE_A | ROLE_B | ROLE_C, user1));
        assertFalse(access.hasRootRoles(ROLE_A | ROLE_B | ROLE_C | ROLE_D, user1));
        
        // Grant one more role and test again
        access.grantRoles(access.ROOT_RESOURCE(), ROLE_C | ROLE_D | ADMIN_ROLE, user1);
        
        // Now combinations with A, B, C and D should work
        assertTrue(access.hasRootRoles(ROLE_A | ROLE_B | ROLE_C | ROLE_D | ADMIN_ROLE, user1));
    }

    function test_revoke_roles() public {
        // Create roles with ROLE_D as the admin
        uint256 roleBitmapA = ROLE_A | ADMIN_ROLE;
        uint256 roleBitmapB = ROLE_B | ADMIN_ROLE_2;
        uint256 roleBitmapC = ROLE_C | ADMIN_ROLE_3;
        
        // Grant multiple roles to user1 in different resources
        access.grantRoles(RESOURCE_1, roleBitmapA, user1);
        access.grantRoles(RESOURCE_1, roleBitmapB, user1);
        access.grantRoles(RESOURCE_2, roleBitmapA, user1);
        
        // Verify initial state
        assertTrue(access.hasRoles(RESOURCE_1, roleBitmapA | roleBitmapB, user1));
        assertTrue(access.hasRoles(RESOURCE_2, roleBitmapA, user1));
        
        // Basic revocation test
        vm.recordLogs();
        bool success = access.revokeRoles(RESOURCE_1, roleBitmapA, user1);
        
        // Verify success and role was revoked
        assertTrue(success);
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ADMIN_ROLE, user1));

        assertTrue(access.hasRoles(RESOURCE_1, roleBitmapB, user1)); // Other role shouldn't be affected

        // Verify role in other resource was not affected
        assertTrue(access.hasRoles(RESOURCE_2, roleBitmapA, user1));

        // Verify event was emitted correctly
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EACRolesRevoked(bytes32,uint256,address,address)"));
        (bytes32 resource, uint256 roles, address account, address sender) = abi.decode(entries[0].data, (bytes32, uint256, address, address));
        assertEq(resource, RESOURCE_1);
        assertEq(roles, roleBitmapA);
        assertEq(account, user1);
        assertEq(sender, address(this));
        
        // Test revoking a non-existent role (should not emit events)
        vm.recordLogs();
        success = access.revokeRoles(RESOURCE_1, roleBitmapA, user1);
        
        // Verify no changes and failure return
        assertFalse(success);
        assertFalse(access.hasRoles(RESOURCE_1, roleBitmapA, user1));
        entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
        
        // Test revoking a mix of existing and non-existing roles
        // First grant ROLE_C to user1 (user1 already has ROLE_B from earlier)
        access.grantRoles(RESOURCE_1, roleBitmapC, user1);
        
        // Verify initial state: user1 has ROLE_B and ROLE_C
        assertTrue(access.hasRoles(RESOURCE_1, roleBitmapB | roleBitmapC, user1));
        
        // Now revoke ROLE_C so user1 only has ROLE_B
        access.revokeRoles(RESOURCE_1, roleBitmapC, user1);
        assertTrue(access.hasRoles(RESOURCE_1, roleBitmapB, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_C, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ADMIN_ROLE_3, user1));
        
        // Record logs for the mixed revocation test
        vm.recordLogs();
        
        // Create a bitmap for ROLE_B and ROLE_C with ADMIN_ROLE_2 as admin
        uint256 mixedRoleBitmap = roleBitmapB | ROLE_C;
        
        // Now try to revoke both ROLE_B and ADMIN_ROLE_2 (which user1 has) and ROLE_C (which user1 doesn't have)
        success = access.revokeRoles(RESOURCE_1, mixedRoleBitmap, user1);
        
        // Verify success (at least one role was revoked)
        assertTrue(success);
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_B, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_C, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ADMIN_ROLE_2, user1));

        // Verify event was emitted correctly
        entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EACRolesRevoked(bytes32,uint256,address,address)"));
        (resource, roles, account, sender) = abi.decode(entries[0].data, (bytes32, uint256, address, address));
        assertEq(resource, RESOURCE_1);
        assertEq(roles, mixedRoleBitmap);
        assertEq(account, user1);
        assertEq(sender, address(this));
        
        // Verify roles for RESOURCE_2 were still not affected
        assertTrue(access.hasRoles(RESOURCE_2, roleBitmapA, user1));
    }

    // Test that unauthorized accounts cannot revoke roles
    function test_revoke_roles_unauthorizedAdmin() public {
        // Create a bitmap with roles ROLE_A with ADMIN_ROLE as the admin
        uint256 roleBitmap = ROLE_A | ADMIN_ROLE;

        // Grant ROLE_A to user2, as the test admin
        access.grantRoles(RESOURCE_1, roleBitmap, user2);
        
        // Verify user2 has ROLE_A and ADMIN_ROLE
        assertTrue(access.hasRoles(RESOURCE_1, roleBitmap, user2));
        
        // user1 attempts to revoke ROLE_A from user2, but doesn't have ADMIN_ROLE admin
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountAdminRoles.selector, RESOURCE_1, roleBitmap, user1));
        access.revokeRoles(RESOURCE_1, roleBitmap, user2);
        
        // Verify user2 still has ROLE_A (it wasn't revoked)
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user2));
    }

    function test_revoke_all_roles() public {
        // Setup: Grant multiple roles to user1
        access.grantRoles(RESOURCE_1, ROLE_A | ADMIN_ROLE, user1);
        access.grantRoles(RESOURCE_1, ROLE_B | ADMIN_ROLE, user1);
        access.grantRoles(RESOURCE_2, ROLE_A | ADMIN_ROLE, user1);
        
        // Verify initial state
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B | ADMIN_ROLE, user1));
        assertTrue(access.hasRoles(RESOURCE_2, ROLE_A | ADMIN_ROLE, user1));
        
        // Record logs to verify event emission
        vm.recordLogs();
        
        // Revoke all roles for RESOURCE_1
        bool success = access.revokeAllRoles(RESOURCE_1, user1);
        
        // Verify the operation was successful
        assertTrue(success);
        
        // Verify all roles for RESOURCE_1 were revoked
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_B, user1));
        assertFalse(access.hasRoles(RESOURCE_1, ADMIN_ROLE, user1));

        // Verify roles for RESOURCE_2 were not affected
        assertTrue(access.hasRoles(RESOURCE_2, ROLE_A | ADMIN_ROLE, user1));
        
        // Verify event was emitted correctly
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EACRolesRevoked(bytes32,uint256,address,address)"));
        (bytes32 resource, uint256 roles, address account, address sender) = abi.decode(entries[0].data, (bytes32, uint256, address, address));
        assertEq(resource, RESOURCE_1);
        // Check that the revoked bitmap includes both roles (and admin bits)
        assertTrue((roles & ROLE_A) == ROLE_A);
        assertTrue((roles & ROLE_B) == ROLE_B);
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

    function test_supports_interface() public view {
        assertTrue(access.supportsInterface(type(EnhancedAccessControl).interfaceId));
    }

    function test_root_resource_role_applies_to_all_resources() public {
        access.grantRoles(access.ROOT_RESOURCE(), ROLE_A | ADMIN_ROLE, user1);
        
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ADMIN_ROLE, user1));
        assertTrue(access.hasRoles(RESOURCE_2, ROLE_A | ADMIN_ROLE, user1));
        assertTrue(access.hasRoles(bytes32(keccak256("ANY_OTHER_RESOURCE")), ROLE_A | ADMIN_ROLE, user1));
    }

    function test_copy_roles() public {
        // Setup: Grant multiple roles to user1
        access.grantRoles(RESOURCE_1, ROLE_B | ADMIN_ROLE, user1);
        access.grantRoles(RESOURCE_1, ROLE_A | ADMIN_ROLE, user1);
        access.grantRoles(RESOURCE_2, ROLE_A | ADMIN_ROLE, user1);
        
        // Verify initial state
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B | ADMIN_ROLE, user1));
        assertTrue(access.hasRoles(RESOURCE_2, ROLE_A | ADMIN_ROLE, user1));

        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A, user2));
        assertFalse(access.hasRoles(RESOURCE_1, ADMIN_ROLE, user2));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_B, user2));
        assertFalse(access.hasRoles(RESOURCE_1, ADMIN_ROLE, user2));
        assertFalse(access.hasRoles(RESOURCE_2, ROLE_A, user2));
        assertFalse(access.hasRoles(RESOURCE_2, ADMIN_ROLE, user2));

        // Record logs to verify event emission
        vm.recordLogs();
        
        // Copy roles from user1 to user2 for RESOURCE_1
        access.copyRoles(RESOURCE_1, user1, user2);
        
        // Verify roles were copied correctly for RESOURCE_1
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B | ADMIN_ROLE, user2));
        
        // Verify roles for RESOURCE_2 were not copied
        assertFalse(access.hasRoles(RESOURCE_2, ROLE_A, user2));
        assertFalse(access.hasRoles(RESOURCE_2, ADMIN_ROLE, user2));

        // Verify user1 still has all original roles
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B | ADMIN_ROLE, user1));
        assertTrue(access.hasRoles(RESOURCE_2, ROLE_A | ADMIN_ROLE, user1));
        
        // Verify event was emitted correctly
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EACRolesCopied(bytes32,bytes32,address,address,uint256)"));
        (bytes32 srcResource, bytes32 dstResource, address srcAccount, address dstAccount, uint256 roleBitmap) = abi.decode(entries[0].data, (bytes32, bytes32, address, address, uint256));
        assertEq(srcResource, RESOURCE_1);
        assertEq(dstResource, RESOURCE_1);
        assertEq(srcAccount, user1);
        assertEq(dstAccount, user2);
        
        // Check that the bitmap includes all roles (note: admin bits will be included too)
        assertTrue((roleBitmap & ROLE_A) == ROLE_A);
        assertTrue((roleBitmap & ROLE_B) == ROLE_B);
        assertTrue((roleBitmap & ADMIN_ROLE) == ADMIN_ROLE);
    }

    function test_copy_roles_bitwise_or() public {
        // Setup: Grant different roles to user1 and user2
        access.grantRoles(RESOURCE_1, ROLE_A | ADMIN_ROLE, user1);
        access.grantRoles(RESOURCE_1, ROLE_B | ADMIN_ROLE, user1);
        access.grantRoles(RESOURCE_1, ROLE_C | ADMIN_ROLE, user2);
        access.grantRoles(RESOURCE_1, ROLE_D | ADMIN_ROLE, user2);
        
        // Verify initial state
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B | ADMIN_ROLE, user1));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_C | ROLE_D | ADMIN_ROLE, user2));
        
        // Record logs to verify event emission
        vm.recordLogs();

        // Copy roles from user1 to user2 for RESOURCE_1
        // This should OR the roles, not overwrite them
        access.copyRoles(RESOURCE_1, user1, user2);
        
        // Verify user2 now has all roles (original + copied)
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B | ROLE_C | ROLE_D | ADMIN_ROLE, user2));
        
        // Verify event was emitted correctly
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EACRolesCopied(bytes32,bytes32,address,address,uint256)"));
        (bytes32 srcResource, bytes32 dstResource, address srcAccount, address dstAccount, uint256 roleBitmap) = abi.decode(entries[0].data, (bytes32, bytes32, address, address, uint256));
        assertEq(srcResource, RESOURCE_1);
        assertEq(dstResource, RESOURCE_1);
        assertEq(srcAccount, user1);
        assertEq(dstAccount, user2);
        // The bitmap should include ROLE_A and ROLE_B (and admin bits)
        assertTrue((roleBitmap & ROLE_A) == ROLE_A);
        assertTrue((roleBitmap & ROLE_B) == ROLE_B);
    }
    
    // function test_check_self_role_escalation() public {
    //     // Grant ROLE_A to user1, with ADMIN_ROLE as the admin
    //     access.grantRoles(RESOURCE_1, ROLE_A | ADMIN_ROLE, user1);
        
    //     // Grant ROLE_B to user1, with ADMIN_ROLE_2 as the admin
    //     access.grantRoles(RESOURCE_1, ROLE_B | ADMIN_ROLE_2, user1);
        
    //     // Verify user1 has ROLE_A and ROLE_B but not ROLE_C or ROLE_D
    //     assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ADMIN_ROLE, user1));
    //     assertTrue(access.hasRoles(RESOURCE_1, ROLE_B | ADMIN_ROLE_2, user1));
    //     assertFalse(access.hasRoles(RESOURCE_1, ROLE_C, user1));
    //     assertFalse(access.hasRoles(RESOURCE_1, ROLE_D, user1));
        
    //     // User1 attempts to grant themselves ROLE_D (which would be dangerous as it's the admin for ROLE_A)
    //     // using ROLE_A or ROLE_B as admin
    //     uint256 roleDWithAdminA = access.createRoleWithAdmin(ROLE_D, ROLE_A);
    //     uint256 roleDWithAdminB = access.createRoleWithAdmin(ROLE_D, ROLE_B);
        
    //     // Both of these should succeed because user1 has both ROLE_A and ROLE_B
    //     // This demonstrates that if you use existing roles as admins for higher privilege roles,
    //     // users could escalate their privileges
    //     vm.startPrank(user1);
        
    //     // First with ROLE_A as admin
    //     access.grantRoles(RESOURCE_1, roleDWithAdminA, user1);
        
    //     // Confirm user1 now has ROLE_D
    //     assertTrue(access.hasRoles(RESOURCE_1, ROLE_D, user1));
        
    //     // Revoke ROLE_D for the next test
    //     access.revokeRoles(RESOURCE_1, roleDWithAdminA, user1);
    //     assertFalse(access.hasRoles(RESOURCE_1, ROLE_D, user1));
        
    //     // Now with ROLE_B as admin
    //     access.grantRoles(RESOURCE_1, roleDWithAdminB, user1);
        
    //     // Confirm user1 now has ROLE_D again
    //     assertTrue(access.hasRoles(RESOURCE_1, ROLE_D, user1));
        
    //     vm.stopPrank();
        
    //     // This test demonstrates that proper role hierarchy must be maintained
    //     // when designing the system to prevent privilege escalation
    // }
}