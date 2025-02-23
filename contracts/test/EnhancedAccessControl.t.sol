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
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EnhancedAccessControlUnauthorizedAccount.selector, CONTEXT_1, access.DEFAULT_ADMIN_ROLE(), user1));
        vm.prank(user1);
        access.grantRole(CONTEXT_1, ROLE_A, user2);
    }

    function test_Revert_unauthorized_revoke() public {
        access.grantRole(CONTEXT_1, ROLE_A, user2);
        
        vm.expectRevert(abi.encodeWithSelector(EnhancedAccessControl.EnhancedAccessControlUnauthorizedAccount.selector, CONTEXT_1, access.DEFAULT_ADMIN_ROLE(), user1));
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
} 