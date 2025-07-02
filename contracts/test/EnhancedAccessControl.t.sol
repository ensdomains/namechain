// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {EnhancedAccessControl} from "../src/common/EnhancedAccessControl.sol";

abstract contract MockRoles {
    bytes32 public constant RESOURCE_1 = bytes32(keccak256("RESOURCE_1"));
    bytes32 public constant RESOURCE_2 = bytes32(keccak256("RESOURCE_2"));

    uint256 public constant ROLE_A = 0x1;        // First nybble (bits 0-3)
    uint256 public constant ROLE_B = 0x10;       // Second nybble (bits 4-7)
    uint256 public constant ROLE_C = 0x100;      // Third nybble (bits 8-11)
    uint256 public constant ROLE_D = 0x1000;     // Fourth nybble (bits 12-15)
    uint256 public constant ADMIN_ROLE_A = 0x1 << 128;    // First admin nybble (bits 128-131)
    uint256 public constant ADMIN_ROLE_B = 0x10 << 128;   // Second admin nybble (bits 132-135)
    uint256 public constant ADMIN_ROLE_C = 0x100 << 128;  // Third admin nybble (bits 136-139)
    uint256 public constant ADMIN_ROLE_D = 0x1000 << 128; // Fourth admin nybble (bits 140-143)
}

contract MockEnhancedAccessControl is EnhancedAccessControl, MockRoles {
    uint256 public lastGrantedCount;
    uint256 public lastGrantedRoleBitmap;
    uint256 public lastGrantedUpdatedRoles;
    uint256 public lastGrantedOldRoles;
    uint256 public lastGrantedNewRoles;
    address public lastGrantedAccount;
    bytes32 public lastGrantedResource;
    
    uint256 public lastRevokedCount;
    uint256 public lastRevokedRoleBitmap;
    uint256 public lastRevokedUpdatedRoles;
    uint256 public lastRevokedOldRoles;
    uint256 public lastRevokedNewRoles;
    address public lastRevokedAccount;
    bytes32 public lastRevokedResource;

    constructor() EnhancedAccessControl() {
        _grantRoles(ROOT_RESOURCE, ROLE_A | ROLE_B | ROLE_C | ROLE_D | ADMIN_ROLE_A | ADMIN_ROLE_B | ADMIN_ROLE_C | ADMIN_ROLE_D, msg.sender, true);
        lastGrantedCount = 0;
        lastRevokedCount = 0;
        lastGrantedResource = bytes32(0);
        lastRevokedResource = bytes32(0);
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

    function copyRoles(bytes32 resource, address srcAccount, address dstAccount) external {
        _copyRoles(resource, srcAccount, dstAccount, true);
    }

    function revokeAllRoles(bytes32 resource, address account) external returns (bool) {
        return _revokeAllRoles(resource, account, true);
    }

    function _onRolesGranted(bytes32 resource, address account, uint256 oldRoles, uint256 newRoles, uint256 roleBitmap) internal override {
        lastGrantedCount++;
        lastGrantedResource = resource;
        lastGrantedRoleBitmap = roleBitmap;
        lastGrantedOldRoles = oldRoles;
        lastGrantedNewRoles = newRoles;
        lastGrantedUpdatedRoles = newRoles;
        lastGrantedAccount = account;
    }

    function _onRolesRevoked(bytes32 resource, address account, uint256 oldRoles, uint256 newRoles, uint256 roleBitmap) internal override {
        lastRevokedCount++;
        lastRevokedResource = resource;
        lastRevokedRoleBitmap = roleBitmap;
        lastRevokedOldRoles = oldRoles;
        lastRevokedNewRoles = newRoles;
        lastRevokedUpdatedRoles = newRoles;
        lastRevokedAccount = account;
    }

    function grantRolesWithoutCallback(bytes32 resource, uint256 roleBitmap, address account) external canGrantRoles(resource, roleBitmap) returns (bool) {
        if (resource == ROOT_RESOURCE) {
            revert EACRootResourceNotAllowed();
        }
        return _grantRoles(resource, roleBitmap, account, false);
    }
    
    function revokeRolesWithoutCallback(bytes32 resource, uint256 roleBitmap, address account) external canGrantRoles(resource, roleBitmap) returns (bool) {
        if (resource == ROOT_RESOURCE) {
            revert EACRootResourceNotAllowed();
        }
        return _revokeRoles(resource, roleBitmap, account, false);
    }
    
    function copyRolesWithoutCallback(bytes32 resource, address srcAccount, address dstAccount) external {
        _copyRoles(resource, srcAccount, dstAccount, false);
    }
    
    function revokeAllRolesWithoutCallback(bytes32 resource, address account) external returns (bool) {
        return _revokeAllRoles(resource, account, false);
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
        
        // Create a bitmap with roles ROLE_A, ROLE_B and ADMIN_ROLE_A
        uint256 roleBitmap = ROLE_A | ROLE_B | ADMIN_ROLE_A;
        
        access.grantRoles(RESOURCE_1, roleBitmap, user1);
        
        // Verify all roles were granted
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B | ADMIN_ROLE_A, user1));
        
        // Verify roles were not granted for other resources
        assertFalse(access.hasRoles(RESOURCE_2, ROLE_A, user1));
        assertFalse(access.hasRoles(RESOURCE_2, ROLE_B, user1));
        assertFalse(access.hasRoles(RESOURCE_2, ADMIN_ROLE_A, user1));
        assertFalse(access.hasRoles(RESOURCE_2, ADMIN_ROLE_B, user1));

        // Verify events were emitted
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        
        assertEq(entries[0].topics[0], keccak256("EACRolesGranted(bytes32,uint256,address)"));
        (bytes32 resource, uint256 emittedRoleBitmap, address account) = abi.decode(entries[0].data, (bytes32, uint256, address));
        assertEq(resource, RESOURCE_1);
        assertEq(emittedRoleBitmap, roleBitmap);
        assertEq(account, user1);
        
        // Test granting roles that are already granted (should not emit events)
        vm.recordLogs();
        access.grantRoles(RESOURCE_1, roleBitmap, user1);
        entries = vm.getRecordedLogs();
        assertEq(entries.length, 0);
        
        // Test granting a mix of new and existing roles
        vm.recordLogs();
        uint256 mixedRoleBitmap = ROLE_B | ADMIN_ROLE_B;
        
        access.grantRoles(RESOURCE_1, mixedRoleBitmap, user1);
        
        entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        (bytes32 resource2, uint256 emittedRoleBitmap2, address account2) = abi.decode(entries[0].data, (bytes32, uint256, address));
        assertEq(resource2, RESOURCE_1);
        assertEq(emittedRoleBitmap2, mixedRoleBitmap);
        assertEq(account2, user1);
    }

    // Test that unauthorized accounts cannot grant roles
    function test_grant_roles_unauthorized_admin() public {
        // Grant ROLE_A (but not ADMIN_ROLE_A) to user1
        access.grantRoles(RESOURCE_1, ROLE_A, user1);
        
        // Verify user1 has the roles
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        
        // user1 attempts to grant ROLE_A which requires ADMIN_ROLE_A admin
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountAdminRoles.selector, RESOURCE_1, ROLE_A, user1));
        access.grantRoles(RESOURCE_1, ROLE_A, user2);
    }

    // Test that authorized accounts can grant roles
    function test_grant_roles_authorized_admin() public {
        access.grantRoles(RESOURCE_1, ROLE_A | ADMIN_ROLE_A, user1);
        
        // Verify user1 has the roles
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ADMIN_ROLE_A, user1));
        
        // user1 attempts to grant ROLE_A which requires ADMIN_ROLE_A admin
        vm.prank(user1);
        access.grantRoles(RESOURCE_1, ROLE_A, user2);

        // Verify user2 has the roles
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user2));
    }

    function test_grant_roles_return_value() public {
        uint256 roleBitmap = ROLE_A | ADMIN_ROLE_A;
        
        bool success = access.grantRoles(RESOURCE_1, roleBitmap, user1);
        assertTrue(success);

        // Granting an already granted role should return false
        success = access.grantRoles(RESOURCE_1, roleBitmap, user1);
        assertFalse(success);
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ADMIN_ROLE_A, user1));
    }
    
    // Test that grantRoles cannot be called with ROOT_RESOURCE
    function test_grant_roles_with_root_resource_not_allowed() public {
        bytes32 rootResource = access.ROOT_RESOURCE();
        // Attempt to call grantRoles with ROOT_RESOURCE should revert
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACRootResourceNotAllowed.selector));
        access.grantRoles(rootResource, ROLE_A, user1);
    }

    function test_root_resource_role_applies_to_all_resources() public {
        access.grantRootRoles(ROLE_A, user1);
        
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertTrue(access.hasRoles(RESOURCE_2, ROLE_A, user1));
        assertTrue(access.hasRoles(bytes32(keccak256("ANY_OTHER_RESOURCE")), ROLE_A, user1));
    }

    function test_has_root_roles() public {
        // Initially user1 doesn't have the role in root resource
        assertFalse(access.hasRootRoles(ROLE_A, user1));
        
        // Grant role in root resource using ADMIN_ROLE_A as admin
        access.grantRootRoles(ROLE_A, user1);
        
        // Now user1 should have the role in root resource
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
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, access.ROOT_RESOURCE(), ROLE_A, user2));
        vm.prank(user2);
        access.callOnlyRootRoles(ROLE_A);
        
        // Having the role in a specific resource doesn't satisfy onlyRootRoles
        access.grantRoles(RESOURCE_1, ROLE_A, user2);   
        
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountRoles.selector, access.ROOT_RESOURCE(), ROLE_A, user2));
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
        
        // Now combinations with A, B, C and D should work
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
        
        // Now combinations with A, B, C and D should work
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
        assertEq(entries[0].topics[0], keccak256("EACRolesRevoked(bytes32,uint256,address)"));
        (bytes32 resource, uint256 roles, address account) = abi.decode(entries[0].data, (bytes32, uint256, address));
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
        assertEq(entries[0].topics[0], keccak256("EACRolesRevoked(bytes32,uint256,address)"));
        (resource, roles, account) = abi.decode(entries[0].data, (bytes32, uint256, address));
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
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountAdminRoles.selector, RESOURCE_1, ROLE_A, user1));
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
        
        // Grant admin role to user1
        access.grantRoles(RESOURCE_1, ADMIN_ROLE_A, user1);
        // user1 attempts to revoke ROLE_A from user2, but doesn't have ADMIN_ROLE_A admin
        vm.prank(user1);
        access.revokeRoles(RESOURCE_1, ROLE_A, user2);
        
        // Verify user2 no longer has ROLE_A
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A, user2));
    }
    
    // Test that revokeRoles cannot be called with ROOT_RESOURCE
    function test_revoke_roles_with_root_resource_not_allowed() public {
        bytes32 rootResource = access.ROOT_RESOURCE();
        // Attempt to call revokeRoles with ROOT_RESOURCE should revert
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACRootResourceNotAllowed.selector));
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
        assertEq(entries[0].topics[0], keccak256("EACRolesRevoked(bytes32,uint256,address)"));
        (bytes32 resource, uint256 roles, address account) = abi.decode(entries[0].data, (bytes32, uint256, address));
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
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EACUnauthorizedAccountAdminRoles.selector, access.ROOT_RESOURCE(), ROLE_A, user1));
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
        access.grantRootRoles(ADMIN_ROLE_A, user1);
        
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
        assertEq(entries[0].topics[0], keccak256("EACRolesRevoked(bytes32,uint256,address)"));
        (bytes32 resource, uint256 roles, address account) = abi.decode(entries[0].data, (bytes32, uint256, address));
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
        assertTrue(access.supportsInterface(type(EnhancedAccessControl).interfaceId));
    }

    function test_copy_roles() public {
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
        
        // Copy roles from user1 to user2 for RESOURCE_1
        access.copyRoles(RESOURCE_1, user1, user2);
        
        // Verify roles were copied correctly for RESOURCE_1
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B, user2));
        
        // Verify roles for RESOURCE_2 were not copied
        assertFalse(access.hasRoles(RESOURCE_2, ROLE_A, user2));

        // Verify user1 still has all original roles
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B, user1));
        assertTrue(access.hasRoles(RESOURCE_2, ROLE_A, user1));
        
        // Verify event was emitted correctly
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EACRolesGranted(bytes32,uint256,address)"));
        (bytes32 resource, uint256 roleBitmap, address account) = abi.decode(entries[0].data, (bytes32, uint256, address));
        assertEq(resource, RESOURCE_1);
        assertEq(account, user2);
        
        // Check that the bitmap includes all roles (note: admin bits will be included too)
        assertTrue((roleBitmap & ROLE_A) == ROLE_A);
        assertTrue((roleBitmap & ROLE_B) == ROLE_B);
    }

    function test_copy_roles_bitwise_or() public {
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

        // Copy roles from user1 to user2 for RESOURCE_1
        // This should OR the roles, not overwrite them
        access.copyRoles(RESOURCE_1, user1, user2);
        
        // Verify user2 now has all roles (original + copied)
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B | ROLE_C | ROLE_D, user2));
        
        // Verify event was emitted correctly
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EACRolesGranted(bytes32,uint256,address)"));
        (bytes32 resource, uint256 roleBitmap, address account) = abi.decode(entries[0].data, (bytes32, uint256, address));
        assertEq(resource, RESOURCE_1);
        assertEq(account, user2);
        // The bitmap should include ROLE_A and ROLE_B (and admin bits)
        assertTrue((roleBitmap & ROLE_A) == ROLE_A);
        assertTrue((roleBitmap & ROLE_B) == ROLE_B);
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
        bytes32 prevGrantedResource = access.lastGrantedResource();
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
        assertEq(access.lastRevokedRoleBitmap(), access.ALL_ROLES());
        assertEq(access.lastRevokedOldRoles(), ROLE_B);
        assertEq(access.lastRevokedNewRoles(), 0);
        assertEq(access.lastRevokedUpdatedRoles(), 0); // No roles remain
        assertEq(access.lastRevokedAccount(), user1);
        assertEq(access.lastRevokedCount(), 2);
        
        // Test copying roles
        access.grantRoles(RESOURCE_1, ROLE_A | ROLE_B, user1);
        access.copyRoles(RESOURCE_1, user1, user2);
        
        // Verify grant callback was called for the copy operation
        assertEq(access.lastGrantedResource(), RESOURCE_1);
        assertEq(access.lastGrantedRoleBitmap(), ROLE_A | ROLE_B);
        assertEq(access.lastGrantedOldRoles(), 0);
        assertEq(access.lastGrantedNewRoles(), ROLE_A | ROLE_B);
        assertEq(access.lastGrantedUpdatedRoles(), ROLE_A | ROLE_B);
        assertEq(access.lastGrantedAccount(), user2);
        assertEq(access.lastGrantedCount(), 3);
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
        
        // Test copyRoles without callback
        access.grantRoles(RESOURCE_1, ROLE_A | ROLE_B, user1);
        uint256 grantCountBeforeCopy = access.lastGrantedCount();
        
        access.copyRolesWithoutCallback(RESOURCE_1, user1, user2);
        
        // Verify grant callback was not called for the copy
        assertEq(access.lastGrantedCount(), grantCountBeforeCopy);
        
        // But the roles should be copied
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A | ROLE_B, user2));
        
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
        
        // Copy roles and verify
        access.copyRoles(RESOURCE_1, user1, user2);
        assertEq(access.roles(RESOURCE_1, user2), ROLE_A | ROLE_B | ROLE_C | ROLE_D);
        
        // Verify root resource roles from user1 were not copied
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
        bool directCheck = (access.roles(RESOURCE_1, user1) & (ROLE_A | ROLE_B)) == (ROLE_A | ROLE_B);
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
}