// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {AddrRegistrar, ROLE_SET_NAME, ROLE_SET_NAME_ADMIN} from "~src/reverse/AddrRegistrar.sol";
import {IEnhancedAccessControl} from "~src/access-control/interfaces/IEnhancedAccessControl.sol";
import {MockHCAFactoryBasic} from "~test/mocks/MockHCAFactoryBasic.sol";

contract AddrRegistrarTest is Test {
    MockHCAFactoryBasic hcaFactory;
    AddrRegistrar registrar;

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");

    string name1 = "user1.eth";
    string name2 = "user2.xyz";

    function setUp() external {
        hcaFactory = new MockHCAFactoryBasic();
        registrar = new AddrRegistrar(hcaFactory);
    }

    function test_reclaim() external {
        vm.expectEmit();
        emit AddrRegistrar.ResourceChanged(user1, 0, 1);
        vm.expectEmit();
        emit AddrRegistrar.NameChanged(user1, name1, user1);
        vm.prank(user1);
        registrar.reclaim(name1);
        assertEq(registrar.getName(user1), name1, "name");
        assertTrue(
            registrar.hasRoles(
                registrar.getResource(user1),
                ROLE_SET_NAME | ROLE_SET_NAME_ADMIN,
                user1
            ),
            "roles"
        );
    }

    function test_reclaimWithAdmin() external {
        vm.expectEmit();
        emit AddrRegistrar.ResourceChanged(user1, 0, 1);
        vm.expectEmit();
        emit AddrRegistrar.NameChanged(user1, name1, user1);
        vm.prank(user1);
        registrar.reclaimWithAdmin(name1, user2);
        assertEq(registrar.getName(user1), name1, "name");
        uint256 resource = registrar.getResource(user1);
        assertFalse(registrar.hasRoles(resource, ROLE_SET_NAME | ROLE_SET_NAME_ADMIN, user1), "1");
        assertTrue(registrar.hasRoles(resource, ROLE_SET_NAME | ROLE_SET_NAME_ADMIN, user2), "2");
    }

    function test_setName() external {
        vm.prank(user1);
        registrar.reclaimWithAdmin(name1, user2);

        vm.prank(user2);
        registrar.setName(user1, name2);

        assertEq(registrar.getName(user1), name2, "name");
    }

    function test_setName_notAuthorized() external {
        vm.prank(user1);
        registrar.reclaim(name1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                registrar.getResource(user1),
                ROLE_SET_NAME,
                user2
            )
        );
        vm.prank(user2);
        registrar.setName(user1, name1);
    }

    function test_authorize() external {
        vm.prank(user1);
        registrar.reclaim(name1);

        // user2 cannot change
        vm.expectRevert();
        vm.prank(user2);
        registrar.setName(user1, name2);

        // grant user2
        vm.prank(user1);
        registrar.authorize(user1, user2, true);

        // user2 can change
        vm.prank(user2);
        registrar.setName(user1, name2);

        // revoke user2
        vm.prank(user1);
        registrar.authorize(user1, user2, false);

        // user2 cannot change
        vm.expectRevert();
        vm.prank(user2);
        registrar.setName(user1, name2);
    }

    function test_authorize_notAuthorized() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                0,
                ROLE_SET_NAME,
                user1
            )
        );
        vm.prank(user1);
        registrar.authorize(user1, user2, true);
    }

    function test_getName_unset() external view {
        assertEq(registrar.getName(user1), "");
    }

    function test_getResource_lifecycle() external {
        assertEq(registrar.getResource(user1), 0);
        assertEq(registrar.getResource(user2), 0);
        vm.prank(user1);
        registrar.reclaim(name1);
        assertEq(registrar.getResource(user1), 1);
        assertEq(registrar.getResource(user2), 0);
        vm.prank(user2);
        registrar.reclaim(name2);
        assertEq(registrar.getResource(user1), 1);
        assertEq(registrar.getResource(user2), 2);
    }

    function test_getResourceMax_lifecycle() external {
        assertEq(registrar.getResourceMax(), 0);
        registrar.reclaim("");
        assertEq(registrar.getResourceMax(), 1);
        registrar.reclaim("");
        assertEq(registrar.getResourceMax(), 2);
    }
}
