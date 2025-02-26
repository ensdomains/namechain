// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {EnhancedAccessControl} from "../src/registry/EnhancedAccessControl.sol";

contract MockEnhancedAccessControl is EnhancedAccessControl {
    constructor() {
        _grantRole(ROOT_CONTEXT, DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setRoleAdmin(bytes32 role, bytes32 adminRole) external {
        _setRoleAdmin(role, adminRole);
    }

    function revokeRoleAssignments(bytes32 context, bytes32 role) external {
        _revokeRoleAssignments(context, role);
    }
    
    function callOnlyRootRole(bytes32 role) external onlyRootRole(role) {
        // Function that will revert if caller doesn't have the role in root context
    }

    function setRoleGroup(bytes32 roleGroup, bytes32[] memory roles) external {
        _setRoleGroup(roleGroup, roles);
    }

    function callOnlyRoleGroup(bytes32 context, bytes32 roleGroup) external onlyRoleGroup(context, roleGroup) {
        // Function that will revert if caller doesn't have any role in the role group for the context
    }
}

contract EnhancedAccessControlTest is Test {
    bytes32 public constant ROLE_A = keccak256("ROLE_A");
    bytes32 public constant ROLE_B = keccak256("ROLE_B");
    bytes32 public constant CONTEXT_1 = bytes32(keccak256("CONTEXT_1"));
    bytes32 public constant CONTEXT_2 = bytes32(keccak256("CONTEXT_2"));

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
        assertTrue(access.hasRole(CONTEXT_1, access.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(access.hasRole(CONTEXT_2, access.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_grant_role() public {
        vm.recordLogs();
        
        access.grantRole(CONTEXT_1, ROLE_A, user1);
        
        assertTrue(access.hasRole(CONTEXT_1, ROLE_A, user1));
        assertFalse(access.hasRole(CONTEXT_2, ROLE_A, user1));

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EnhancedAccessControlRoleGranted(bytes32,bytes32,address,address)"));
        (bytes32 context, bytes32 role, address account, address sender) = abi.decode(entries[0].data, (bytes32, bytes32, address, address));
        assertEq(context, CONTEXT_1);
        assertEq(role, ROLE_A);
        assertEq(account, user1);
        assertEq(sender, address(this));
    }

    function test_has_root_role() public {
        // Initially user1 doesn't have the role in root context
        assertFalse(access.hasRootRole(ROLE_A, user1));
        
        // Grant role in root context
        access.grantRole(access.ROOT_CONTEXT(), ROLE_A, user1);
        
        // Now user1 should have the role in root context
        assertTrue(access.hasRootRole(ROLE_A, user1));
        
        // Revoking the role should remove it
        access.revokeRole(access.ROOT_CONTEXT(), ROLE_A, user1);
        assertFalse(access.hasRootRole(ROLE_A, user1));
        
        // Having a role in a specific context doesn't mean having it in root context
        access.grantRole(CONTEXT_1, ROLE_A, user1);
        assertFalse(access.hasRootRole(ROLE_A, user1));
    }

    function test_only_root_role() public {
        // Grant role in root context to user1
        access.grantRole(access.ROOT_CONTEXT(), ROLE_A, user1);
        
        // User1 should be able to call function with onlyRootRole modifier
        vm.prank(user1);
        access.callOnlyRootRole(ROLE_A);
        
        // User2 doesn't have the role, should revert
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EnhancedAccessControlUnauthorizedAccountRole.selector, access.ROOT_CONTEXT(), ROLE_A, user2));
        vm.prank(user2);
        access.callOnlyRootRole(ROLE_A);
        
        // Having the role in a specific context doesn't satisfy onlyRootRole
        access.grantRole(CONTEXT_1, ROLE_A, user2);
        
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EnhancedAccessControlUnauthorizedAccountRole.selector, access.ROOT_CONTEXT(), ROLE_A, user2));
        vm.prank(user2);
        access.callOnlyRootRole(ROLE_A);
    }

    function test_grant_role_return_value() public {
        bool success = access.grantRole(CONTEXT_1, ROLE_A, user1);
        assertTrue(success);

        // Granting an already granted role should return false
        success = access.grantRole(CONTEXT_1, ROLE_A, user1);
        assertFalse(success);
        assertTrue(access.hasRole(CONTEXT_1, ROLE_A, user1));
    }

    function test_revoke_role() public {
        access.grantRole(CONTEXT_1, ROLE_A, user1);
        
        vm.recordLogs();
        access.revokeRole(CONTEXT_1, ROLE_A, user1);
        
        assertFalse(access.hasRole(CONTEXT_1, ROLE_A, user1));

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EnhancedAccessControlRoleRevoked(bytes32,bytes32,address,address)"));
        (bytes32 context, bytes32 role, address account, address sender) = abi.decode(entries[0].data, (bytes32, bytes32, address, address));
        assertEq(context, CONTEXT_1);
        assertEq(role, ROLE_A);
        assertEq(account, user1);
        assertEq(sender, address(this));
    }

    function test_renounce_role() public {
        vm.startPrank(user1);
        access.renounceRole(CONTEXT_1, ROLE_A, user1);
        assertFalse(access.hasRole(CONTEXT_1, ROLE_A, user1));
        vm.stopPrank();
    }

    function test_set_role_admin() public {
        vm.recordLogs();
        access.setRoleAdmin(ROLE_A, ROLE_B);
        
        assertEq(access.getRoleAdmin(ROLE_A), ROLE_B);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EnhancedAccessControlRoleAdminChanged(bytes32,bytes32,bytes32)"));
        (bytes32 role, bytes32 previousAdmin, bytes32 newAdmin) = abi.decode(entries[0].data, (bytes32, bytes32, bytes32));
        assertEq(role, ROLE_A);
        assertEq(previousAdmin, bytes32(0));
        assertEq(newAdmin, ROLE_B);

        access.grantRole(CONTEXT_1, ROLE_B, user1);

        vm.prank(user1);
        access.grantRole(CONTEXT_1, ROLE_A, user2);
        assertTrue(access.hasRole(CONTEXT_1, ROLE_A, user2));

        vm.prank(user1);
        access.revokeRole(CONTEXT_1, ROLE_A, user2);
        assertFalse(access.hasRole(CONTEXT_1, ROLE_A, user2));
    }

    function test_Revert_unauthorized_grant() public {
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EnhancedAccessControlUnauthorizedAccountRole.selector, CONTEXT_1, access.DEFAULT_ADMIN_ROLE(), user1));
        vm.prank(user1);
        access.grantRole(CONTEXT_1, ROLE_A, user2);
    }

    function test_Revert_unauthorized_revoke() public {
        access.grantRole(CONTEXT_1, ROLE_A, user2);
        
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EnhancedAccessControlUnauthorizedAccountRole.selector, CONTEXT_1, access.DEFAULT_ADMIN_ROLE(), user1));
        vm.prank(user1);
        access.revokeRole(CONTEXT_1, ROLE_A, user2);
    }

    function test_Revert_bad_renounce_confirmation() public {
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EnhancedAccessControlBadConfirmation.selector));
        vm.prank(user1);
        access.renounceRole(CONTEXT_1, ROLE_A, user2);
    }

    function test_role_isolation() public {
        access.grantRole(CONTEXT_1, ROLE_A, user1);
        assertTrue(access.hasRole(CONTEXT_1, ROLE_A, user1));
        assertFalse(access.hasRole(CONTEXT_2, ROLE_A, user1));
    }

    function test_supports_interface() public view {
        assertTrue(access.supportsInterface(type(EnhancedAccessControl).interfaceId));
    }

    function test_revoke_role_assignments() public {
        access.grantRole(CONTEXT_1, ROLE_A, user1);
        access.grantRole(CONTEXT_1, ROLE_A, user2);
        access.grantRole(CONTEXT_1, ROLE_B, user1);
        
        access.revokeRoleAssignments(CONTEXT_1, ROLE_A);
        
        assertFalse(access.hasRole(CONTEXT_1, ROLE_A, user1));
        assertFalse(access.hasRole(CONTEXT_1, ROLE_A, user2));
        assertTrue(access.hasRole(CONTEXT_1, ROLE_B, user1));
    }

    function test_root_context_role_applies_to_all_contexts() public {
        access.grantRole(access.ROOT_CONTEXT(), ROLE_A, user1);
        
        assertTrue(access.hasRole(CONTEXT_1, ROLE_A, user1));
        assertTrue(access.hasRole(CONTEXT_2, ROLE_A, user1));
        assertTrue(access.hasRole(bytes32(keccak256("ANY_OTHER_CONTEXT")), ROLE_A, user1));
    }

    bytes32 public constant ROLE_GROUP_1 = keccak256("ROLE_GROUP_1");

    function test_set_role_group() public {
        bytes32[] memory roles = new bytes32[](2);
        roles[0] = ROLE_A;
        roles[1] = ROLE_B;

        vm.recordLogs();
        access.setRoleGroup(ROLE_GROUP_1, roles);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("EnhancedAccessControlRoleGroupChanged(bytes32,bytes32[],bytes32[])"));
        
        // Verify event data
        (bytes32 roleGroup, bytes32[] memory previousRoles, bytes32[] memory newRoles) = abi.decode(
            entries[0].data, 
            (bytes32, bytes32[], bytes32[])
        );
        
        assertEq(roleGroup, ROLE_GROUP_1);
        assertEq(previousRoles.length, 0);
        assertEq(newRoles.length, 2);
        assertEq(newRoles[0], ROLE_A);
        assertEq(newRoles[1], ROLE_B);
    }

    function test_only_role_group() public {
        // Setup role group with ROLE_A and ROLE_B
        bytes32[] memory roles = new bytes32[](2);
        roles[0] = ROLE_A;
        roles[1] = ROLE_B;
        access.setRoleGroup(ROLE_GROUP_1, roles);

        // Grant ROLE_A to user1
        access.grantRole(CONTEXT_1, ROLE_A, user1);
        
        // User1 should be able to call function with onlyRoleGroup modifier
        vm.prank(user1);
        access.callOnlyRoleGroup(CONTEXT_1, ROLE_GROUP_1);
        
        // Grant ROLE_B to user2
        access.grantRole(CONTEXT_1, ROLE_B, user2);
        
        // User2 should also be able to call the function
        vm.prank(user2);
        access.callOnlyRoleGroup(CONTEXT_1, ROLE_GROUP_1);
        
        // User without any role in the group should not be able to call the function
        address user3 = makeAddr("user3");
        vm.expectRevert(abi.encodeWithSelector(
            EnhancedAccessControl.EnhancedAccessControlUnauthorizedAccountRoleGroup.selector, 
            CONTEXT_1, 
            ROLE_GROUP_1, 
            user3
        ));
        vm.prank(user3);
        access.callOnlyRoleGroup(CONTEXT_1, ROLE_GROUP_1);
    }

    function test_modify_role_group() public {
        // Setup initial role group with ROLE_A
        bytes32[] memory roles = new bytes32[](1);
        roles[0] = ROLE_A;
        access.setRoleGroup(ROLE_GROUP_1, roles);
        
        // Grant ROLE_A to user1
        access.grantRole(CONTEXT_1, ROLE_A, user1);
        
        // User1 should be able to call function with onlyRoleGroup modifier
        vm.prank(user1);
        access.callOnlyRoleGroup(CONTEXT_1, ROLE_GROUP_1);
        
        // Modify role group to only contain ROLE_B
        bytes32[] memory newRoles = new bytes32[](1);
        newRoles[0] = ROLE_B;
        
        vm.recordLogs();
        access.setRoleGroup(ROLE_GROUP_1, newRoles);
        
        // User1 should no longer be able to call the function
        vm.expectRevert(abi.encodeWithSelector(
            EnhancedAccessControl.EnhancedAccessControlUnauthorizedAccountRoleGroup.selector, 
            CONTEXT_1, 
            ROLE_GROUP_1, 
            user1
        ));
        vm.prank(user1);
        access.callOnlyRoleGroup(CONTEXT_1, ROLE_GROUP_1);
        
        // Grant ROLE_B to user1
        access.grantRole(CONTEXT_1, ROLE_B, user1);
        
        // Now user1 should be able to call the function again
        vm.prank(user1);
        access.callOnlyRoleGroup(CONTEXT_1, ROLE_GROUP_1);
    }

    function test_root_role_in_role_group() public {
        // Setup role group with ROLE_A
        bytes32[] memory roles = new bytes32[](1);
        roles[0] = ROLE_A;
        access.setRoleGroup(ROLE_GROUP_1, roles);
        
        // Grant ROLE_A in root context to user1
        access.grantRole(access.ROOT_CONTEXT(), ROLE_A, user1);
        
        // User1 should be able to call function with onlyRoleGroup modifier for any context
        vm.prank(user1);
        access.callOnlyRoleGroup(CONTEXT_1, ROLE_GROUP_1);
        
        vm.prank(user1);
        access.callOnlyRoleGroup(CONTEXT_2, ROLE_GROUP_1);
        
        vm.prank(user1);
        access.callOnlyRoleGroup(bytes32(keccak256("ANY_OTHER_CONTEXT")), ROLE_GROUP_1);
    }

    function test_empty_role_group() public {
        // Setup empty role group
        bytes32[] memory roles = new bytes32[](0);
        access.setRoleGroup(ROLE_GROUP_1, roles);
        
        // User should not be able to call the function with empty role group
        vm.expectRevert(abi.encodeWithSelector(
            EnhancedAccessControl.EnhancedAccessControlUnauthorizedAccountRoleGroup.selector, 
            CONTEXT_1, 
            ROLE_GROUP_1, 
            user1
        ));
        vm.prank(user1);
        access.callOnlyRoleGroup(CONTEXT_1, ROLE_GROUP_1);
    }
} 