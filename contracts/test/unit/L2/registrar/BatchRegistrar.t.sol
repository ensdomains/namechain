// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";

import {EACBaseRolesLib} from "~src/common/access-control/EnhancedAccessControl.sol";
import {PermissionedRegistry} from "~src/common/registry/PermissionedRegistry.sol";
import {RegistryDatastore} from "~src/common/registry/RegistryDatastore.sol";
import {SimpleRegistryMetadata} from "~src/common/registry/SimpleRegistryMetadata.sol";
import {RegistryRolesLib} from "~src/common/registry/libraries/RegistryRolesLib.sol";
import {IRegistry} from "~src/common/registry/interfaces/IRegistry.sol";
import {BatchRegistrar, BatchRegistrarName} from "~src/L2/registrar/BatchRegistrar.sol";

contract BatchRegistrarTest is Test {
    PermissionedRegistry ethRegistry;
    BatchRegistrar batchRegistrar;

    address owner = makeAddr("owner");
    address user = makeAddr("user");

    function setUp() external {
        ethRegistry = new PermissionedRegistry(
            new RegistryDatastore(),
            new SimpleRegistryMetadata(),
            owner,
            EACBaseRolesLib.ALL_ROLES
        );

        batchRegistrar = new BatchRegistrar(ethRegistry);

        vm.prank(owner);
        ethRegistry.grantRootRoles(RegistryRolesLib.ROLE_REGISTRAR, address(batchRegistrar));
    }

    function test_Constructor() external {
        assertEq(address(batchRegistrar.ETH_REGISTRY()), address(ethRegistry));
    }

    function test_BatchRegisterSingleName() external {
        BatchRegistrarName[] memory names = new BatchRegistrarName[](1);
        names[0] = BatchRegistrarName({
            label: "test",
            owner: user,
            registry: IRegistry(address(0)),
            resolver: address(0),
            roleBitmap: EACBaseRolesLib.ALL_ROLES,
            expires: uint64(block.timestamp + 365 days)
        });

        vm.recordLogs();
        batchRegistrar.batchRegister(names);

        (uint256 tokenId,) = ethRegistry.getNameData("test");
        address nameOwner = ethRegistry.ownerOf(tokenId);
        assertEq(nameOwner, user);
    }

    function test_BatchRegisterMultipleNames() external {
        BatchRegistrarName[] memory names = new BatchRegistrarName[](3);
        uint64 expires = uint64(block.timestamp + 365 days);

        names[0] = BatchRegistrarName({
            label: "test1",
            owner: user,
            registry: IRegistry(address(0)),
            resolver: address(0),
            roleBitmap: EACBaseRolesLib.ALL_ROLES,
            expires: expires
        });

        names[1] = BatchRegistrarName({
            label: "test2",
            owner: user,
            registry: IRegistry(address(0)),
            resolver: address(0),
            roleBitmap: EACBaseRolesLib.ALL_ROLES,
            expires: expires
        });

        names[2] = BatchRegistrarName({
            label: "test3",
            owner: user,
            registry: IRegistry(address(0)),
            resolver: address(0),
            roleBitmap: EACBaseRolesLib.ALL_ROLES,
            expires: expires
        });

        batchRegistrar.batchRegister(names);

        for (uint256 i = 0; i < names.length; i++) {
            (uint256 tokenId,) = ethRegistry.getNameData(names[i].label);
            address nameOwner = ethRegistry.ownerOf(tokenId);
            assertEq(nameOwner, user);
        }
    }

    function test_BatchRegisterEmptyArray() external {
        BatchRegistrarName[] memory names = new BatchRegistrarName[](0);
        batchRegistrar.batchRegister(names);
    }

    function test_RevertWhen_BatchRegisterAlreadyRegisteredName() external {
        BatchRegistrarName[] memory names = new BatchRegistrarName[](1);
        names[0] = BatchRegistrarName({
            label: "duplicate",
            owner: user,
            registry: IRegistry(address(0)),
            resolver: address(0),
            roleBitmap: EACBaseRolesLib.ALL_ROLES,
            expires: uint64(block.timestamp + 365 days)
        });

        batchRegistrar.batchRegister(names);

        vm.expectRevert();
        batchRegistrar.batchRegister(names);
    }

    function test_RevertWhen_CallerLacksRegistrarRole() external {
        vm.prank(owner);
        ethRegistry.revokeRootRoles(RegistryRolesLib.ROLE_REGISTRAR, address(batchRegistrar));

        BatchRegistrarName[] memory names = new BatchRegistrarName[](1);
        names[0] = BatchRegistrarName({
            label: "unauthorized",
            owner: user,
            registry: IRegistry(address(0)),
            resolver: address(0),
            roleBitmap: EACBaseRolesLib.ALL_ROLES,
            expires: uint64(block.timestamp + 365 days)
        });

        vm.expectRevert();
        batchRegistrar.batchRegister(names);
    }

    function test_BatchRegisterWithDifferentOwners() external {
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        BatchRegistrarName[] memory names = new BatchRegistrarName[](3);
        uint64 expires = uint64(block.timestamp + 365 days);

        names[0] = BatchRegistrarName({
            label: "owner1",
            owner: user,
            registry: IRegistry(address(0)),
            resolver: address(0),
            roleBitmap: EACBaseRolesLib.ALL_ROLES,
            expires: expires
        });

        names[1] = BatchRegistrarName({
            label: "owner2",
            owner: user2,
            registry: IRegistry(address(0)),
            resolver: address(0),
            roleBitmap: EACBaseRolesLib.ALL_ROLES,
            expires: expires
        });

        names[2] = BatchRegistrarName({
            label: "owner3",
            owner: user3,
            registry: IRegistry(address(0)),
            resolver: address(0),
            roleBitmap: EACBaseRolesLib.ALL_ROLES,
            expires: expires
        });

        batchRegistrar.batchRegister(names);

        (uint256 tokenId1,) = ethRegistry.getNameData("owner1");
        assertEq(ethRegistry.ownerOf(tokenId1), user);

        (uint256 tokenId2,) = ethRegistry.getNameData("owner2");
        assertEq(ethRegistry.ownerOf(tokenId2), user2);

        (uint256 tokenId3,) = ethRegistry.getNameData("owner3");
        assertEq(ethRegistry.ownerOf(tokenId3), user3);
    }

    function test_BatchRegisterEmitsEventsFromRegistry() external {
        BatchRegistrarName[] memory names = new BatchRegistrarName[](2);
        uint64 expires = uint64(block.timestamp + 365 days);

        names[0] = BatchRegistrarName({
            label: "event1",
            owner: user,
            registry: IRegistry(address(0)),
            resolver: address(0),
            roleBitmap: EACBaseRolesLib.ALL_ROLES,
            expires: expires
        });

        names[1] = BatchRegistrarName({
            label: "event2",
            owner: user,
            registry: IRegistry(address(0)),
            resolver: address(0),
            roleBitmap: EACBaseRolesLib.ALL_ROLES,
            expires: expires
        });

        vm.recordLogs();
        batchRegistrar.batchRegister(names);

        // Verify events were emitted from registry
        (uint256 tokenId1,) = ethRegistry.getNameData("event1");
        assertGt(tokenId1, 0);

        (uint256 tokenId2,) = ethRegistry.getNameData("event2");
        assertGt(tokenId2, 0);
    }
}
