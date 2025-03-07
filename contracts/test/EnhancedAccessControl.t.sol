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

    function copyRoles(bytes32 srcResource, address srcAccount, bytes32 dstResource, address dstAccount) external {
        _copyRoles(srcResource, srcAccount, dstResource, dstAccount);
    }

    function revokeAllRoles(bytes32 resource, address account) external returns (bool) {
        return _revokeAllRoles(resource, account);
    }
    
    function grantRoles(bytes32 resource, uint256 roleBitmap, address account) external returns (bool) {
        return _grantRoles(resource, roleBitmap, account);
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
        
        assertEq(entries[0].topics[0], keccak256("EnhancedAccessControlRolesGranted(bytes32,uint256,address,address)"));
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
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EnhancedAccessControlUnauthorizedAccountRole.selector, access.ROOT_RESOURCE(), ROLE_A, user2));
        vm.prank(user2);
        access.callOnlyRootRole(ROLE_A);
        
        // Having the role in a specific resource doesn't satisfy onlyRootRole
        access.grantRole(RESOURCE_1, ROLE_A, user2);
        
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EnhancedAccessControlUnauthorizedAccountRole.selector, access.ROOT_RESOURCE(), ROLE_A, user2));
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
        assertEq(entries[0].topics[0], keccak256("EnhancedAccessControlRolesRevoked(bytes32,uint256,address,address)"));
        (bytes32 resource, uint256 roles, address account, address sender) = abi.decode(entries[0].data, (bytes32, uint256, address, address));
        assertEq(resource, RESOURCE_1);
        assertEq(roles, ROLE_A);
        assertEq(account, user1);
        assertEq(sender, address(this));
    }

    function test_renounce_role() public {
        vm.startPrank(user1);
        access.renounceRole(RESOURCE_1, ROLE_A, user1);
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        vm.stopPrank();
    }

    function test_set_role_admin() public {
        vm.recordLogs();
        access.setRoleAdmin(ROLE_A, ROLE_B);
        
        assertEq(access.getRoleAdmin(ROLE_A), ROLE_B);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EnhancedAccessControlRoleAdminChanged(uint256,uint256,uint256)"));
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
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EnhancedAccessControlUnauthorizedAccountAdminRole.selector, RESOURCE_1, ROLE_A, user1));
        vm.prank(user1);
        access.grantRole(RESOURCE_1, ROLE_A, user2);
    }

    function test_Revert_unauthorized_revoke() public {
        access.grantRole(RESOURCE_1, ROLE_A, user2);
        
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EnhancedAccessControlUnauthorizedAccountAdminRole.selector, RESOURCE_1, ROLE_A, user1));
        vm.prank(user1);
        access.revokeRole(RESOURCE_1, ROLE_A, user2);
    }

    function test_Revert_bad_renounce_confirmation() public {
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EnhancedAccessControlBadConfirmation.selector));
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
        access.copyRoles(RESOURCE_1, user1, RESOURCE_1, user2);
        
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
        assertEq(entries[0].topics[0], keccak256("EnhancedAccessControlRolesCopied(bytes32,bytes32,address,address,uint256)"));
        (bytes32 srcResource, bytes32 dstResource, address srcAccount, address dstAccount, uint256 roleBitmap) = abi.decode(entries[0].data, (bytes32, bytes32, address, address, uint256));
        assertEq(srcResource, RESOURCE_1);
        assertEq(dstResource, RESOURCE_1);
        assertEq(srcAccount, user1);
        assertEq(dstAccount, user2);
        // The bitmap should have bits set for ROLE_A and ROLE_B
        assertEq(roleBitmap, ROLE_A | ROLE_B);
    }

    function test_copy_roles_between_resources() public {
        // Setup: Grant multiple roles to user1
        access.grantRole(RESOURCE_1, ROLE_A, user1);
        access.grantRole(RESOURCE_1, ROLE_B, user1);
        
        // Verify initial state
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_B, user1));
        assertFalse(access.hasRoles(RESOURCE_2, ROLE_A, user1));
        assertFalse(access.hasRoles(RESOURCE_2, ROLE_B, user1));
        
        // Record logs to verify event emission
        vm.recordLogs();
        
        // Copy roles from RESOURCE_1 to RESOURCE_2 for user1
        access.copyRoles(RESOURCE_1, user1, RESOURCE_2, user1);
        
        // Verify roles were copied correctly to RESOURCE_2
        assertTrue(access.hasRoles(RESOURCE_2, ROLE_A, user1));
        assertTrue(access.hasRoles(RESOURCE_2, ROLE_B, user1));
        
        // Verify original roles in RESOURCE_1 are still intact
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user1));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_B, user1));
        
        // Verify event was emitted correctly
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EnhancedAccessControlRolesCopied(bytes32,bytes32,address,address,uint256)"));
        (bytes32 srcResource, bytes32 dstResource, address srcAccount, address dstAccount, uint256 roleBitmap) = abi.decode(entries[0].data, (bytes32, bytes32, address, address, uint256));
        assertEq(srcResource, RESOURCE_1);
        assertEq(dstResource, RESOURCE_2);
        assertEq(srcAccount, user1);
        assertEq(dstAccount, user1);
        assertEq(roleBitmap, ROLE_A | ROLE_B);
        
        // Record logs for the second copy operation
        vm.recordLogs();
        
        // Copy roles from user1 to user2 across different resources
        access.copyRoles(RESOURCE_1, user1, RESOURCE_2, user2);
        
        // Verify roles were copied correctly from RESOURCE_1 to RESOURCE_2 for user2
        assertTrue(access.hasRoles(RESOURCE_2, ROLE_A, user2));
        assertTrue(access.hasRoles(RESOURCE_2, ROLE_B, user2));
        
        // Verify user2 doesn't have roles in RESOURCE_1
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_A, user2));
        assertFalse(access.hasRoles(RESOURCE_1, ROLE_B, user2));
        
        // Verify event was emitted correctly for the second copy
        entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EnhancedAccessControlRolesCopied(bytes32,bytes32,address,address,uint256)"));
        (srcResource, dstResource, srcAccount, dstAccount, roleBitmap) = abi.decode(entries[0].data, (bytes32, bytes32, address, address, uint256));
        assertEq(srcResource, RESOURCE_1);
        assertEq(dstResource, RESOURCE_2);
        assertEq(srcAccount, user1);
        assertEq(dstAccount, user2);
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
        assertEq(entries[0].topics[0], keccak256("EnhancedAccessControlRolesRevoked(bytes32,uint256,address,address)"));
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
        access.copyRoles(RESOURCE_1, user1, RESOURCE_1, user2);
        
        // Verify user2 now has all roles (original + copied)
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_A, user2));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_B, user2));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_C, user2));
        assertTrue(access.hasRoles(RESOURCE_1, ROLE_D, user2));
        
        // Verify event was emitted correctly with the correct bitmap
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EnhancedAccessControlRolesCopied(bytes32,bytes32,address,address,uint256)"));
        (bytes32 srcResource, bytes32 dstResource, address srcAccount, address dstAccount, uint256 roleBitmap) = abi.decode(entries[0].data, (bytes32, bytes32, address, address, uint256));
        assertEq(srcResource, RESOURCE_1);
        assertEq(dstResource, RESOURCE_1);
        assertEq(srcAccount, user1);
        assertEq(dstAccount, user2);
        assertEq(roleBitmap, ROLE_A | ROLE_B);
    }
} 