// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {
    IRegistry,
    EACBaseRolesLib,
    RegistryRolesLib,
    REGISTRATION_ROLE_BITMAP
} from "~src/L2/registrar/ETHRegistrar.sol";
import {IRegistryDatastore} from "~src/common/registry/interfaces/IRegistryDatastore.sol";
import {L1BridgeController, BridgeRolesLib} from "~src/L1/bridge/L1BridgeController.sol";
import {
    L2BridgeController,
    REQUIRED_EJECTION_ROLES,
    ASSIGNED_INJECTION_ROLES,
    POST_MIGRATION_RESOLVER
} from "~src/L2/bridge/L2BridgeController.sol";
import {TransferData} from "~src/common/bridge/types/TransferData.sol";
import {ETHFixtureMixin} from "~test/fixtures/ETHFixtureMixin.sol";
import {MockL1Bridge} from "~test/mocks/MockL1Bridge.sol";
import {MockL2Bridge} from "~test/mocks/MockL2Bridge.sol";

contract BridgeControllerTest is Test, ETHFixtureMixin, ERC1155Holder {
    ETHFixture ethFixture1;
    ETHFixture ethFixture2;

    MockL1Bridge bridge1;
    MockL2Bridge bridge2;

    L1BridgeController controller1;
    L2BridgeController controller2;

    address user = makeAddr("user");
    IRegistry testRegistry = IRegistry(makeAddr("testRegistry"));
    address testResolver = makeAddr("testResolver");

    function setUp() external {
        ethFixture1 = deployETHFixture();
        ethFixture2 = deployETHFixture();

        bridge1 = new MockL1Bridge();
        bridge2 = new MockL2Bridge();

        controller1 = new L1BridgeController(bridge1, ethFixture1.ethRegistry);
        controller2 = new L2BridgeController(bridge2, ethFixture2.ethRegistry);

        bridge1.setReceiverBridge(bridge2);
        bridge2.setReceiverBridge(bridge1);

        bridge1.setBridgeController(controller1);
        bridge2.setBridgeController(controller2);

        controller1.grantRootRoles(BridgeRolesLib.ROLE_EJECTOR, address(bridge1));
        controller2.grantRootRoles(BridgeRolesLib.ROLE_EJECTOR, address(bridge2));

        ethFixture1.ethRegistry.grantRootRoles(
            RegistryRolesLib.ROLE_REGISTRAR |
                RegistryRolesLib.ROLE_RENEW |
                RegistryRolesLib.ROLE_BURN,
            address(controller1)
        );

        // register some names
        for (uint256 i; i < 5; ++i) {
            TransferData memory td;
            td.owner = address(0xf1);
            td.subregistry = IRegistry(address(0xf2));
            td.resolver = address(0xf3);
            td.expiry = _after(100 days);
            td.label = string.concat("a", Strings.toString(i));
            _register(ethFixture1, td);
            td.label = string.concat("b", Strings.toString(i));
            _register(ethFixture1, td);
            td.label = string.concat("c", Strings.toString(i));
            _register(ethFixture2, td);
        }
    }

    function _after(uint256 dt) internal view returns (uint64) {
        return uint64(block.timestamp + dt);
    }

    function _register(ETHFixture memory f, TransferData memory td) internal returns (uint256) {
        return
            f.ethRegistry.register(
                td.label,
                td.owner,
                td.subregistry,
                td.resolver,
                td.roleBitmap,
                td.expiry
            );
    }

    function _assert(ETHFixture memory f, TransferData memory td, string memory tag) internal view {
        (uint256 tokenId, IRegistryDatastore.Entry memory e) = f.ethRegistry.getNameData(td.label);
        assertEq(f.ethRegistry.ownerOf(tokenId), td.owner, string.concat(tag, ".owner"));
        if (td.owner != address(0)) {
            assertEq(
                f.ethRegistry.roles(tokenId, td.owner),
                td.roleBitmap,
                string.concat(tag, ".roles")
            );
        }
        assertEq(f.ethRegistry.getResolver(td.label), td.resolver, string.concat(tag, ".resolver"));
        assertEq(
            address(f.ethRegistry.getSubregistry(td.label)),
            address(td.subregistry),
            string.concat(tag, ".subregistry")
        );
        assertEq(e.expiry, td.expiry, string.concat(tag, ".expiry"));
    }

    function test_roles_REQUIRED_EJECTION_ROLES() external pure {
        assertEq(
            REQUIRED_EJECTION_ROLES ^ RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN,
            REGISTRATION_ROLE_BITMAP
        );
    }

    function test_roles_ASSIGNED_INJECTION_ROLES() external pure {
        assertEq(ASSIGNED_INJECTION_ROLES & REGISTRATION_ROLE_BITMAP, ASSIGNED_INJECTION_ROLES);
    }

    function test_eject2to1to2to1() external {
        TransferData memory td = TransferData({
            label: "test",
            owner: user,
            subregistry: testRegistry,
            resolver: testResolver,
            expiry: _after(1 days),
            roleBitmap: REQUIRED_EJECTION_ROLES
        });

        uint256 tokenId = _register(ethFixture2, td);

        vm.prank(user);
        ethFixture2.ethRegistry.safeTransferFrom(
            user,
            address(controller2),
            tokenId,
            1,
            abi.encode(td)
        );

        td.owner = address(controller2);
        td.resolver = POST_MIGRATION_RESOLVER;
        td.roleBitmap = REQUIRED_EJECTION_ROLES;
        _assert(ethFixture2, td, "1");

        td.owner = user;
        td.resolver = testResolver;
        td.roleBitmap = ASSIGNED_INJECTION_ROLES;
        _assert(ethFixture1, td, "2");

        (tokenId, ) = ethFixture1.ethRegistry.getNameData(td.label);

        vm.prank(user);
        ethFixture1.ethRegistry.safeTransferFrom(
            user,
            address(controller1),
            tokenId,
            1,
            abi.encode(td)
        );

        TransferData memory burned;
        burned.label = td.label;
        _assert(ethFixture1, burned, "3");

        td.roleBitmap = REQUIRED_EJECTION_ROLES;
        _assert(ethFixture2, td, "4");
    }
}
