// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering, one-contract-per-file

import {
    NameWrapper,
    IMetadataService,
    CANNOT_UNWRAP,
    CAN_DO_EVERYTHING,
    CANNOT_BURN_FUSES,
    CANNOT_TRANSFER,
    CANNOT_SET_RESOLVER,
    CANNOT_SET_TTL,
    CANNOT_CREATE_SUBDOMAIN,
    PARENT_CANNOT_CONTROL,
    IS_DOT_ETH,
    CAN_EXTEND_EXPIRY
} from "@ens/contracts/wrapper/NameWrapper.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";

import {MockL1Bridge} from "~test/mocks/MockL1Bridge.sol";
import {NameWrapperFixture} from "~test/fixtures/NameWrapperFixture.sol";
import {ETHRegistryMixin} from "~test/fixtures/ETHRegistryMixin.sol";
import {NameMixin} from "~test/fixtures/NameMixin.sol";
import {BridgeRolesLib} from "~src/common/bridge/libraries/BridgeRolesLib.sol";
import {L1BridgeController, TransferData} from "~src/L1/bridge/L1BridgeController.sol";
import {LockedMigrationController} from "~src/L1/migration/LockedMigrationController.sol";
import {
    MigratedWrappedNameRegistry,
    RegistryRolesLib,
    LockedNamesLib,
    IRegistry
} from "~src/L1/registry/MigratedWrappedNameRegistry.sol";

contract LockedMigrationControllerTest is NameWrapperFixture, ETHRegistryMixin, NameMixin {
    MockL1Bridge bridge;
    L1BridgeController bridgeController;
    LockedMigrationController migrationController;

    VerifiableFactory migratedRegistryFactory;
    MigratedWrappedNameRegistry migratedRegistryImpl;

    function setUp() external {
        _deployNameWrapper();
        _deployETHRegistry();

        bridge = new MockL1Bridge();

        migratedRegistryFactory = new VerifiableFactory();
        migratedRegistryImpl = new MigratedWrappedNameRegistry(
            nameWrapper,
            address(0), // ETHTLDResolver not needed
            migratedRegistryFactory,
            datastore,
            metadata
        );

        bridgeController = new L1BridgeController(ethRegistry, bridge);

        ethRegistry.grantRootRoles(
            RegistryRolesLib.ROLE_REGISTRAR | RegistryRolesLib.ROLE_BURN,
            address(bridgeController)
        );

        migrationController = new LockedMigrationController(
            nameWrapper,
            bridgeController,
            migratedRegistryFactory,
            address(migratedRegistryImpl)
        );

        bridgeController.grantRootRoles(BridgeRolesLib.ROLE_EJECTOR, address(migrationController));
    }

    function _makeData(
        bytes memory name
    ) internal view returns (LockedMigrationController.Data memory) {
        return
            LockedMigrationController.Data({
                node: namehash(name),
                owner: user,
                resolver: address(1),
                salt: uint256(keccak256(abi.encode(name, block.timestamp)))
            });
    }

    // function _migrateETH2LD(
    //     bytes memory name
    // ) internal returns (uint256 tokenId, MigratedWrappedNameRegistry registry) {
    //     tokenId = migrationController.migrate(_makeData(name));
    //     registry = MigratedWrappedNameRegistry(
    //         datastore.getEntry(address(ethRegistry), tokenId).subregistry
    //     );
    // }

    function test_constructor() external view {
        assertEq(
            address(migrationController.ETH_REGISTRY_V1()),
            address(ethRegistrarV1),
            "ETH_REGISTRY_V1"
        );
        assertEq(address(migrationController.NAME_WRAPPER()), address(nameWrapper), "NAME_WRAPPER");
        assertEq(
            address(migrationController.L1_BRIDGE_CONTROLLER()),
            address(bridgeController),
            "L1_BRIDGE_CONTROLLER"
        );
        assertEq(
            address(migrationController.MIGRATED_REGISTRY_FACTORY()),
            address(migratedRegistryFactory),
            "MIGRATED_REGISTRY_FACTORY"
        );
        assertEq(
            migrationController.MIGRATED_REGISTRY_IMPL(),
            address(migratedRegistryImpl),
            "MIGRATED_REGISTRY_IMPL"
        );
        assertEq(migrationController.owner(), address(this), "owner");
    }

    function test_supportsInterface() external view {
        assertTrue(migrationController.supportsInterface(type(IERC165).interfaceId), "IERC165");
        assertTrue(
            migrationController.supportsInterface(type(IERC1155Receiver).interfaceId),
            "IERC1155Receiver"
        );
    }

    function test_migrate_locked() external {
        bytes memory name = registerWrappedETH2LD("test", CANNOT_UNWRAP);
        LockedMigrationController.Data memory md = _makeData(name);
        vm.startPrank(user);
        nameWrapper.safeTransferFrom(
            user,
            address(migrationController),
            uint256(md.node),
            1,
            abi.encode(md)
        );
        vm.stopPrank();
    }

    // ntoe: cannot call CANNOT_BURN_FUSES on ETH2LD
    // function test_migrate_locked_prefrozen() external {
    //     (bytes memory parentName, bytes32 parentNode) = registerWrappedETH2LD(
    //         "test",
    //         CANNOT_UNWRAP
    //     );
    //     (bytes memory name, bytes32 node) = createWrappedChild(
    //         parentNode,
    //         "sub",
    //         PARENT_CANNOT_CONTROL | CANNOT_UNWRAP | CANNOT_BURN_FUSES
    //     );
    //     vm.startPrank(user);
    //     nameWrapper.setApprovalForAll(address(migrationController), true);
    //     (uint256 tokenId, MigratedWrappedNameRegistry parentRegistry) = _migrateETH2LD(parentName);
    //     vm.stopPrank();
    //     MigrationData memory migrationData = MigrationData({
    //         transferData: TransferData({
    //             name: NameCoder.ethName(testLabel),
    //             owner: user,
    //             subregistry: address(0), // Will be created by migratedRegistryFactory
    //             resolver: address(0xABCD),
    //             roleBitmap: RegistryRolesLib.ROLE_SET_RESOLVER, // Note: only regular roles, no admin roles expected
    //             expires: uint64(block.timestamp + 86400)
    //         }),
    //         toL1: true,
    //         salt: uint256(keccak256(abi.encodePacked(testLabel, block.timestamp)))
    //     });
    //     bytes memory data = abi.encode(migrationData);
    //     // Migration should now succeed for names with CANNOT_BURN_FUSES (should not revert)
    //     vm.prank(address(nameWrapper));
    //     migrationController.onERC1155Received(owner, owner, testTokenId, 1, data);
    // }

    /*
    function test_onERC1155Received_locked_name() public {
        // Configure name for locked migration
        uint32 lockedFuses = CANNOT_UNWRAP | IS_DOT_ETH;
        nameWrapper.setFuseData(testTokenId, lockedFuses, uint64(block.timestamp + 86400));

        // Prepare migration data
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                name: NameCoder.ethName(testLabel),
                owner: user,
                subregistry: address(0), // Will be created by migratedRegistryFactory
                resolver: address(0xABCD),
                roleBitmap: RegistryRolesLib.ROLE_SET_RESOLVER |
                    RegistryRolesLib.ROLE_SET_SUBREGISTRY,
                expires: uint64(block.timestamp + 86400)
            }),
            toL1: true,
            salt: uint256(keccak256(abi.encodePacked(testLabel, block.timestamp)))
        });

        bytes memory data = abi.encode(migrationData);

        // Call onERC1155Received
        vm.prank(address(nameWrapper));
        bytes4 selector = migrationController.onERC1155Received(owner, owner, testTokenId, 1, data);

        // Verify selector returned
        assertEq(selector, migrationController.onERC1155Received.selector, "Should return correct selector");

        // Confirm migration finalized the name
        (, uint32 newFuses, ) = nameWrapper.getData(testTokenId);
        assertTrue((newFuses & CANNOT_BURN_FUSES) != 0, "CANNOT_BURN_FUSES should be burnt");
        assertTrue((newFuses & CANNOT_TRANSFER) != 0, "CANNOT_TRANSFER should be burnt");
        assertTrue((newFuses & CANNOT_UNWRAP) != 0, "CANNOT_UNWRAP should be burnt");
        assertTrue((newFuses & CANNOT_SET_RESOLVER) != 0, "CANNOT_SET_RESOLVER should be burnt");
        assertTrue((newFuses & CANNOT_SET_TTL) != 0, "CANNOT_SET_TTL should be burnt");
        assertTrue(
            (newFuses & CANNOT_CREATE_SUBDOMAIN) != 0,
            "CANNOT_CREATE_SUBDOMAIN should be burnt"
        );
    }

    function test_onERC1155Received_roles_based_on_fuses_not_input() public {
        // Configure name with resolver permissions retained
        uint32 lockedFuses = CANNOT_UNWRAP | IS_DOT_ETH | CAN_EXTEND_EXPIRY;
        nameWrapper.setFuseData(testTokenId, lockedFuses, uint64(block.timestamp + 86400));

        // Prepare migration data - the roleBitmap should be ignored completely
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                name: NameCoder.ethName(testLabel),
                owner: user,
                subregistry: address(0), // Will be created by migratedRegistryFactory
                resolver: address(0xABCD),
                roleBitmap: RegistryRolesLib.ROLE_SET_SUBREGISTRY, // This should be completely ignored
                expires: uint64(block.timestamp + 86400)
            }),
            toL1: true,
            salt: uint256(keccak256(abi.encodePacked(testLabel, block.timestamp)))
        });

        bytes memory data = abi.encode(migrationData);

        // Call onERC1155Received
        vm.prank(address(nameWrapper));
        migrationController.onERC1155Received(owner, owner, testTokenId, 1, data);

        // Get the registered name and check roles
        (uint256 registeredTokenId, ) = ethRegistry.getNameData(testLabel);
        uint256 resource = ethRegistry.testGetResourceFromTokenId(registeredTokenId);
        uint256 userRoles = ethRegistry.roles(resource, user);

        // Confirm roles derived from name configuration
        // Since CANNOT_SET_RESOLVER is not burnt, user should have resolver roles
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_SET_RESOLVER) != 0,
            "Should have ROLE_SET_RESOLVER based on fuses"
        );
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN) != 0,
            "Should have ROLE_SET_RESOLVER_ADMIN based on fuses"
        );

        // 2LDs should NOT have renewal roles (CAN_EXTEND_EXPIRY is masked out to prevent automatic renewal for 2LDs)
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_RENEW) == 0,
            "Should NOT have ROLE_RENEW for 2LDs"
        );
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) == 0,
            "Should NOT have ROLE_RENEW_ADMIN for 2LDs"
        );

        // Token should NEVER have registrar roles
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_REGISTRAR) == 0,
            "Token should NEVER have ROLE_REGISTRAR"
        );
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_REGISTRAR_ADMIN) == 0,
            "Token should NEVER have ROLE_REGISTRAR_ADMIN"
        );

        // Should NOT have the role from input data
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_SET_SUBREGISTRY) == 0,
            "Should NOT have ROLE_SET_SUBREGISTRY from input"
        );
    }

    function test_Revert_onERC1155Received_not_locked() public {
        // Configure name that doesn't qualify for locked migration
        uint32 unlockedFuses = IS_DOT_ETH;
        nameWrapper.setFuseData(testTokenId, unlockedFuses, uint64(block.timestamp + 86400));

        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                name: NameCoder.ethName(testLabel),
                owner: user,
                subregistry: address(0), // Will be created by migratedRegistryFactory
                resolver: address(0xABCD),
                roleBitmap: RegistryRolesLib.ROLE_SET_RESOLVER,
                expires: uint64(block.timestamp + 86400)
            }),
            toL1: true,
            salt: uint256(keccak256(abi.encodePacked(testLabel, block.timestamp)))
        });

        bytes memory data = abi.encode(migrationData);

        // Migration should fail for unlocked names
        vm.expectRevert(abi.encodeWithSelector(LibLockedNames.NameNotLocked.selector, testTokenId));
        vm.prank(address(nameWrapper));
        migrationController.onERC1155Received(owner, owner, testTokenId, 1, data);
    }

    function test_name_with_cannot_burn_fuses_can_migrate() public {
        // Configure name with fuses that are permanently frozen - this should now be allowed to migrate
        uint32 fuses = CANNOT_UNWRAP | CANNOT_BURN_FUSES | IS_DOT_ETH | CAN_EXTEND_EXPIRY;
        nameWrapper.setFuseData(testTokenId, fuses, uint64(block.timestamp + 86400));

        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                name: NameCoder.ethName(testLabel),
                owner: user,
                subregistry: address(0), // Will be created by migratedRegistryFactory
                resolver: address(0xABCD),
                roleBitmap: RegistryRolesLib.ROLE_SET_RESOLVER, // Note: only regular roles, no admin roles expected
                expires: uint64(block.timestamp + 86400)
            }),
            toL1: true,
            salt: uint256(keccak256(abi.encodePacked(testLabel, block.timestamp)))
        });

        bytes memory data = abi.encode(migrationData);

        // Migration should now succeed for names with CANNOT_BURN_FUSES (should not revert)
        vm.prank(address(nameWrapper));
        migrationController.onERC1155Received(owner, owner, testTokenId, 1, data);
    }

    function test_Revert_token_id_mismatch() public {
        // Setup locked name
        uint32 lockedFuses = CANNOT_UNWRAP | IS_DOT_ETH;
        nameWrapper.setFuseData(testTokenId, lockedFuses, uint64(block.timestamp + 86400));

        // Use wrong label that doesn't match tokenId
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                name: NameCoder.ethName("wronglabel"), // This won't match testTokenId
                owner: user,
                subregistry: address(0), // Will be created by migratedRegistryFactory
                resolver: address(0xABCD),
                roleBitmap: RegistryRolesLib.ROLE_SET_RESOLVER,
                expires: uint64(block.timestamp + 86400)
            }),
            toL1: true,
            salt: uint256(keccak256(abi.encodePacked(testLabel, block.timestamp)))
        });

        bytes memory data = abi.encode(migrationData);

        // Should revert due to token ID mismatch
        uint256 expectedTokenId = uint256(keccak256(bytes("wronglabel")));
        vm.expectRevert(
            abi.encodeWithSelector(
                LockedMigrationController.TokenIdMismatch.selector,
                testTokenId,
                expectedTokenId
            )
        );
        vm.prank(address(nameWrapper));
        migrationController.onERC1155Received(owner, owner, testTokenId, 1, data);
    }

    function test_Revert_unauthorized_caller() public {
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                name: NameCoder.ethName(testLabel),
                owner: user,
                subregistry: address(0), // Will be created by migratedRegistryFactory
                resolver: address(0xABCD),
                roleBitmap: RegistryRolesLib.ROLE_SET_RESOLVER,
                expires: uint64(block.timestamp + 86400)
            }),
            toL1: true,
            salt: uint256(keccak256(abi.encodePacked(testLabel, block.timestamp)))
        });

        bytes memory data = abi.encode(migrationData);

        // Call from wrong address (not nameWrapper)
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector, address(this)));
        migrationController.onERC1155Received(owner, owner, testTokenId, 1, data);
    }

    function test_onERC1155BatchReceived() public {
        // Setup multiple locked names
        string[] memory labels = new string[](3);
        labels[0] = "test1";
        labels[1] = "test2";
        labels[2] = "test3";

        uint256[] memory tokenIds = new uint256[](3);
        MigrationData[] memory migrationDataArray = new MigrationData[](3);

        for (uint256 i = 0; i < 3; i++) {
            tokenIds[i] = uint256(keccak256(bytes(labels[i])));

            // Setup locked name (CANNOT_BURN_FUSES not set)
            uint32 lockedFuses = CANNOT_UNWRAP | IS_DOT_ETH;
            nameWrapper.setFuseData(tokenIds[i], lockedFuses, uint64(block.timestamp + 86400));

            // DNS encode each label as .eth domain
            bytes memory name;
            if (i == 0) {
                name = NameCoder.ethName("test1");
            } else if (i == 1) {
                name = NameCoder.ethName("test2");
            } else {
                name = NameCoder.ethName("test3");
            }

            migrationDataArray[i] = MigrationData({
                transferData: TransferData({
                    name: name,
                    owner: user,
                    subregistry: address(0), // Will be created by migratedRegistryFactory
                    resolver: address(uint160(0xABCD + i)),
                    roleBitmap: RegistryRolesLib.ROLE_SET_RESOLVER,
                    expires: uint64(block.timestamp + 86400 * (i + 1))
                }),
                toL1: true,
                salt: uint256(keccak256(abi.encodePacked(labels[i], block.timestamp, i)))
            });
        }

        bytes memory data = abi.encode(migrationDataArray);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amounts[1] = amounts[2] = 1;

        // Call batch receive
        vm.prank(address(nameWrapper));
        bytes4 selector = migrationController.onERC1155BatchReceived(owner, owner, tokenIds, amounts, data);

        assertEq(
            selector,
            migrationController.onERC1155BatchReceived.selector,
            "Should return correct selector"
        );

        // Verify all names were processed with all fuses burnt
        for (uint256 i = 0; i < 3; i++) {
            (, uint32 newFuses, ) = nameWrapper.getData(tokenIds[i]);
            assertTrue((newFuses & CANNOT_BURN_FUSES) != 0, "CANNOT_BURN_FUSES should be burnt");
            assertTrue((newFuses & CANNOT_TRANSFER) != 0, "CANNOT_TRANSFER should be burnt");
            assertTrue((newFuses & CANNOT_UNWRAP) != 0, "CANNOT_UNWRAP should be burnt");
            assertTrue(
                (newFuses & CANNOT_SET_RESOLVER) != 0,
                "CANNOT_SET_RESOLVER should be burnt"
            );
            assertTrue((newFuses & CANNOT_SET_TTL) != 0, "CANNOT_SET_TTL should be burnt");
            assertTrue(
                (newFuses & CANNOT_CREATE_SUBDOMAIN) != 0,
                "CANNOT_CREATE_SUBDOMAIN should be burnt"
            );
        }
    }

    function test_subregistry_creation() public {
        // Setup locked name (CANNOT_BURN_FUSES not set)
        uint32 lockedFuses = CANNOT_UNWRAP | IS_DOT_ETH;
        nameWrapper.setFuseData(testTokenId, lockedFuses, uint64(block.timestamp + 86400));

        // Prepare migration data with unique salt
        uint256 saltData = uint256(keccak256(abi.encodePacked(testLabel, uint256(999))));
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                name: NameCoder.ethName(testLabel),
                owner: user,
                subregistry: address(0), // Will be created by migratedRegistryFactory
                resolver: address(0xABCD),
                roleBitmap: RegistryRolesLib.ROLE_SET_RESOLVER,
                expires: uint64(block.timestamp + 86400)
            }),
            toL1: true,
            salt: saltData
        });

        bytes memory data = abi.encode(migrationData);

        // Call onERC1155Received
        vm.prank(address(nameWrapper));
        migrationController.onERC1155Received(owner, owner, testTokenId, 1, data);

        // Verify a subregistry was created
        address actualSubregistry = address(ethRegistry.getSubregistry(testLabel));
        assertTrue(actualSubregistry != address(0), "Subregistry should be created");

        // Verify it's a proxy pointing to our implementation
        // The migratedRegistryFactory creates a proxy, so we can verify it's pointing to the right implementation
        MigratedWrappedNameRegistry migratedRegistry = MigratedWrappedNameRegistry(
            actualSubregistry
        );
        assertEq(
            migratedRegistry.parentDnsEncodedName(),
            "\x04test\x03eth\x00",
            "Should have correct parent DNS name"
        );
    }

    // Comprehensive fuse→role mapping tests

    function test_fuse_role_mapping_no_fuses_burnt() public {
        // Setup locked name with only CANNOT_UNWRAP (no other fuses burnt)
        uint32 lockedFuses = CANNOT_UNWRAP | IS_DOT_ETH | CAN_EXTEND_EXPIRY;
        nameWrapper.setFuseData(testTokenId, lockedFuses, uint64(block.timestamp + 86400));

        // Prepare migration data - incoming roleBitmap should be ignored
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                name: NameCoder.ethName(testLabel),
                owner: user,
                subregistry: address(0), // Will be created by migratedRegistryFactory
                resolver: address(0xABCD),
                roleBitmap: RegistryRolesLib.ROLE_SET_SUBREGISTRY, // This should be ignored
                expires: uint64(block.timestamp + 86400)
            }),
            toL1: true,
            salt: uint256(keccak256(abi.encodePacked(testLabel, block.timestamp)))
        });

        bytes memory data = abi.encode(migrationData);

        // Call onERC1155Received
        vm.prank(address(nameWrapper));
        migrationController.onERC1155Received(owner, owner, testTokenId, 1, data);

        // Get the registered name and check roles
        (uint256 registeredTokenId, ) = ethRegistry.getNameData(testLabel);
        uint256 resource = ethRegistry.testGetResourceFromTokenId(registeredTokenId);
        uint256 userRoles = ethRegistry.roles(resource, user);

        // 2LDs should NOT have renewal roles even when no additional fuses are burnt (CAN_EXTEND_EXPIRY is masked out to prevent automatic renewal for 2LDs)
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_RENEW) == 0,
            "Should NOT have ROLE_RENEW for 2LDs"
        );
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) == 0,
            "Should NOT have ROLE_RENEW_ADMIN for 2LDs"
        );
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_SET_RESOLVER) != 0,
            "Should have ROLE_SET_RESOLVER"
        );
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN) != 0,
            "Should have ROLE_SET_RESOLVER_ADMIN"
        );

        // Token should NEVER have registrar roles
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_REGISTRAR) == 0,
            "Token should NEVER have ROLE_REGISTRAR"
        );
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_REGISTRAR_ADMIN) == 0,
            "Token should NEVER have ROLE_REGISTRAR_ADMIN"
        );

        // Verify incoming roleBitmap was ignored
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_SET_SUBREGISTRY) == 0,
            "Should NOT have ROLE_SET_SUBREGISTRY from incoming data"
        );
    }

    function test_fuse_role_mapping_no_extend_expiry_fuse() public {
        // Setup locked name WITHOUT CAN_EXTEND_EXPIRY fuse
        uint32 lockedFuses = CANNOT_UNWRAP | IS_DOT_ETH;
        nameWrapper.setFuseData(testTokenId, lockedFuses, uint64(block.timestamp + 86400));

        // Prepare migration data
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                name: NameCoder.ethName(testLabel),
                owner: user,
                subregistry: address(0), // Will be created by migratedRegistryFactory
                resolver: address(0xABCD),
                roleBitmap: 0,
                expires: uint64(block.timestamp + 86400)
            }),
            toL1: true,
            salt: uint256(keccak256(abi.encodePacked(testLabel, block.timestamp)))
        });

        bytes memory data = abi.encode(migrationData);

        // Call onERC1155Received
        vm.prank(address(nameWrapper));
        migrationController.onERC1155Received(owner, owner, testTokenId, 1, data);

        // Get the registered name and check roles
        (uint256 registeredTokenId, ) = ethRegistry.getNameData(testLabel);
        uint256 resource = ethRegistry.testGetResourceFromTokenId(registeredTokenId);
        uint256 userRoles = ethRegistry.roles(resource, user);

        // Should NOT have renewal roles since CAN_EXTEND_EXPIRY is not set
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_RENEW) == 0,
            "Should NOT have ROLE_RENEW without CAN_EXTEND_EXPIRY"
        );
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) == 0,
            "Should NOT have ROLE_RENEW_ADMIN without CAN_EXTEND_EXPIRY"
        );
        // Should have resolver roles since CANNOT_SET_RESOLVER is not set
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_SET_RESOLVER) != 0,
            "Should have ROLE_SET_RESOLVER"
        );
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN) != 0,
            "Should have ROLE_SET_RESOLVER_ADMIN"
        );
    }

    function test_fuse_role_mapping_resolver_fuse_burnt() public {
        // Setup locked name with CANNOT_SET_RESOLVER already burnt
        uint32 lockedFuses = CANNOT_UNWRAP | CANNOT_SET_RESOLVER | IS_DOT_ETH | CAN_EXTEND_EXPIRY;
        nameWrapper.setFuseData(testTokenId, lockedFuses, uint64(block.timestamp + 86400));

        // Prepare migration data
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                name: NameCoder.ethName(testLabel),
                owner: user,
                subregistry: address(0), // Will be created by migratedRegistryFactory
                resolver: address(0xABCD),
                roleBitmap: RegistryRolesLib.ROLE_SET_RESOLVER |
                    RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN, // Should be ignored
                expires: uint64(block.timestamp + 86400)
            }),
            toL1: true,
            salt: uint256(keccak256(abi.encodePacked(testLabel, block.timestamp)))
        });

        bytes memory data = abi.encode(migrationData);

        // Call onERC1155Received
        vm.prank(address(nameWrapper));
        migrationController.onERC1155Received(owner, owner, testTokenId, 1, data);

        // Get the registered name and check roles
        (uint256 registeredTokenId, ) = ethRegistry.getNameData(testLabel);
        uint256 resource = ethRegistry.testGetResourceFromTokenId(registeredTokenId);
        uint256 userRoles = ethRegistry.roles(resource, user);

        // 2LDs should NOT have renewal roles even when CANNOT_CREATE_SUBDOMAIN is not burnt (CAN_EXTEND_EXPIRY is masked out to prevent automatic renewal for 2LDs)
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_RENEW) == 0,
            "Should NOT have ROLE_RENEW for 2LDs"
        );
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) == 0,
            "Should NOT have ROLE_RENEW_ADMIN for 2LDs"
        );

        // Token should NEVER have registrar roles
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_REGISTRAR) == 0,
            "Token should NEVER have ROLE_REGISTRAR"
        );
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_REGISTRAR_ADMIN) == 0,
            "Token should NEVER have ROLE_REGISTRAR_ADMIN"
        );

        // Should NOT have resolver roles since CANNOT_SET_RESOLVER is burnt
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_SET_RESOLVER) == 0,
            "Should NOT have ROLE_SET_RESOLVER"
        );
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN) == 0,
            "Should NOT have ROLE_SET_RESOLVER_ADMIN"
        );
    }

    function test_fuse_role_mapping_cannot_create_subdomain_burnt() public {
        // Setup locked name with CANNOT_CREATE_SUBDOMAIN burnt
        uint32 lockedFuses = CANNOT_UNWRAP |
            CANNOT_CREATE_SUBDOMAIN |
            IS_DOT_ETH |
            CAN_EXTEND_EXPIRY;
        nameWrapper.setFuseData(testTokenId, lockedFuses, uint64(block.timestamp + 86400));

        // Prepare migration data
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                name: NameCoder.ethName(testLabel),
                owner: user,
                subregistry: address(0), // Will be created by migratedRegistryFactory
                resolver: address(0xABCD),
                roleBitmap: RegistryRolesLib.ROLE_REGISTRAR | RegistryRolesLib.ROLE_REGISTRAR_ADMIN, // Should be ignored
                expires: uint64(block.timestamp + 86400)
            }),
            toL1: true,
            salt: uint256(keccak256(abi.encodePacked(testLabel, block.timestamp)))
        });

        bytes memory data = abi.encode(migrationData);

        // Call onERC1155Received
        vm.prank(address(nameWrapper));
        migrationController.onERC1155Received(owner, owner, testTokenId, 1, data);

        // Get the registered name and check roles
        (uint256 registeredTokenId, ) = ethRegistry.getNameData(testLabel);
        uint256 resource = ethRegistry.testGetResourceFromTokenId(registeredTokenId);
        uint256 userRoles = ethRegistry.roles(resource, user);

        // 2LDs should NOT have renewal roles (CAN_EXTEND_EXPIRY is masked out to prevent automatic renewal for 2LDs) but should have resolver roles
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_RENEW) == 0,
            "Should NOT have ROLE_RENEW for 2LDs"
        );
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_RENEW_ADMIN) == 0,
            "Should NOT have ROLE_RENEW_ADMIN for 2LDs"
        );
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_SET_RESOLVER) != 0,
            "Should have ROLE_SET_RESOLVER"
        );
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_SET_RESOLVER_ADMIN) != 0,
            "Should have ROLE_SET_RESOLVER_ADMIN"
        );

        // Should NOT have registrar roles since CANNOT_CREATE_SUBDOMAIN is burnt
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_REGISTRAR) == 0,
            "Should NOT have ROLE_REGISTRAR when subdomain creation disabled"
        );
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_REGISTRAR_ADMIN) == 0,
            "Should NOT have ROLE_REGISTRAR_ADMIN when subdomain creation disabled"
        );

        // Verify incoming roleBitmap was ignored
        assertTrue(
            (userRoles & RegistryRolesLib.ROLE_SET_SUBREGISTRY) == 0,
            "Should NOT have ROLE_SET_SUBREGISTRY from incoming data"
        );
    }

    function test_fuses_burnt_after_migration_completes() public {
        // Setup locked name (CANNOT_BURN_FUSES not set so migration can proceed)
        uint32 initialFuses = CANNOT_UNWRAP | IS_DOT_ETH;
        nameWrapper.setFuseData(testTokenId, initialFuses, uint64(block.timestamp + 86400));

        // Prepare migration data
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                name: NameCoder.ethName(testLabel),
                owner: user,
                subregistry: address(0), // Will be created by migratedRegistryFactory
                resolver: address(0xABCD),
                roleBitmap: RegistryRolesLib.ROLE_SET_SUBREGISTRY, // Should be ignored
                expires: uint64(block.timestamp + 86400)
            }),
            toL1: true,
            salt: uint256(keccak256(abi.encodePacked(testLabel, block.timestamp)))
        });

        bytes memory data = abi.encode(migrationData);

        // Call onERC1155Received
        vm.prank(address(nameWrapper));
        migrationController.onERC1155Received(owner, owner, testTokenId, 1, data);

        // Verify that ALL required fuses are burnt (migration completed, then fuses burnt)
        (, uint32 finalFuses, ) = nameWrapper.getData(testTokenId);

        // Check that all required fuses are burnt
        assertTrue((finalFuses & CANNOT_UNWRAP) != 0, "CANNOT_UNWRAP should remain burnt");
        assertTrue(
            (finalFuses & CANNOT_BURN_FUSES) != 0,
            "CANNOT_BURN_FUSES should be burnt after migration"
        );
        assertTrue(
            (finalFuses & CANNOT_TRANSFER) != 0,
            "CANNOT_TRANSFER should be burnt after migration"
        );
        assertTrue(
            (finalFuses & CANNOT_SET_RESOLVER) != 0,
            "CANNOT_SET_RESOLVER should be burnt after migration"
        );
        assertTrue(
            (finalFuses & CANNOT_SET_TTL) != 0,
            "CANNOT_SET_TTL should be burnt after migration"
        );
        assertTrue(
            (finalFuses & CANNOT_CREATE_SUBDOMAIN) != 0,
            "CANNOT_CREATE_SUBDOMAIN should be burnt after migration"
        );

        // Verify name was successfully migrated despite all fuses being burnt after
        (uint256 registeredTokenId, ) = ethRegistry.getNameData(testLabel);
        assertTrue(registeredTokenId != 0, "Name should be successfully registered");
    }

    function test_Revert_invalid_non_eth_name() public {
        // Setup locked name without IS_DOT_ETH fuse (not a .eth domain)
        uint32 lockedFuses = CANNOT_UNWRAP; // Missing IS_DOT_ETH
        nameWrapper.setFuseData(testTokenId, lockedFuses, uint64(block.timestamp + 86400));

        // Prepare migration data
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                name: NameCoder.ethName(testLabel),
                owner: user,
                subregistry: address(0), // Will be created by migratedRegistryFactory
                resolver: address(0xABCD),
                roleBitmap: RegistryRolesLib.ROLE_SET_SUBREGISTRY,
                expires: uint64(block.timestamp + 86400)
            }),
            toL1: true,
            salt: uint256(keccak256(abi.encodePacked(testLabel, block.timestamp)))
        });

        bytes memory data = abi.encode(migrationData);

        // Should revert because IS_DOT_ETH fuse is not set
        vm.expectRevert(abi.encodeWithSelector(LibLockedNames.NotDotEthName.selector, testTokenId));
        vm.prank(address(nameWrapper));
        migrationController.onERC1155Received(owner, owner, testTokenId, 1, data);
    }

    function test_subregistry_owner_roles() public {
        // Setup locked name
        uint32 lockedFuses = CANNOT_UNWRAP | IS_DOT_ETH;
        nameWrapper.setFuseData(testTokenId, lockedFuses, uint64(block.timestamp + 86400));

        // Prepare migration data with user as owner
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                name: NameCoder.ethName(testLabel),
                owner: user,
                subregistry: address(0), // Will be created by migratedRegistryFactory
                resolver: address(0xABCD),
                roleBitmap: RegistryRolesLib.ROLE_SET_RESOLVER,
                expires: uint64(block.timestamp + 86400)
            }),
            toL1: true,
            salt: uint256(keccak256(abi.encodePacked(testLabel, "owner_test")))
        });

        bytes memory data = abi.encode(migrationData);

        // Call onERC1155Received
        vm.prank(address(nameWrapper));
        migrationController.onERC1155Received(owner, owner, testTokenId, 1, data);

        // Get the registered name and check subregistry owner
        IRegistry subregistry = ethRegistry.getSubregistry(testLabel);

        // Verify the user is the owner of the subregistry with only UPGRADE roles
        IPermissionedRegistry subRegistry = IPermissionedRegistry(address(subregistry));

        // The user should only have UPGRADE and UPGRADE_ADMIN roles on the subregistry
        // ROLE_UPGRADE = 1 << 20, ROLE_UPGRADE_ADMIN = ROLE_UPGRADE << 128
        uint256 ROLE_UPGRADE = 1 << 20;
        uint256 ROLE_UPGRADE_ADMIN = ROLE_UPGRADE << 128;
        uint256 upgradeRoles = ROLE_UPGRADE | ROLE_UPGRADE_ADMIN;
        assertTrue(
            subRegistry.hasRootRoles(upgradeRoles, user),
            "User should have UPGRADE roles on subregistry"
        );
    }

    function test_freezeName_clears_resolver_when_fuse_not_set() public {
        // Setup locked name with CANNOT_SET_RESOLVER fuse NOT set
        uint32 lockedFuses = CANNOT_UNWRAP | IS_DOT_ETH;
        nameWrapper.setFuseData(testTokenId, lockedFuses, uint64(block.timestamp + 86400));

        // Set an initial resolver on the name
        address initialResolver = address(0x9999);
        nameWrapper.setInitialResolver(testTokenId, initialResolver);

        // Verify resolver is initially set
        assertEq(
            nameWrapper.getResolver(testTokenId),
            initialResolver,
            "Initial resolver should be set"
        );

        // Prepare migration data
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                name: NameCoder.ethName(testLabel),
                owner: user,
                subregistry: address(0), // Will be created by migratedRegistryFactory
                resolver: address(0xABCD),
                roleBitmap: RegistryRolesLib.ROLE_SET_RESOLVER,
                expires: uint64(block.timestamp + 86400)
            }),
            toL1: true,
            salt: uint256(keccak256(abi.encodePacked(testLabel, block.timestamp)))
        });

        bytes memory data = abi.encode(migrationData);

        // Call onERC1155Received
        vm.prank(address(nameWrapper));
        migrationController.onERC1155Received(owner, owner, testTokenId, 1, data);

        // Verify resolver was cleared to address(0)
        assertEq(
            nameWrapper.getResolver(testTokenId),
            address(0),
            "Resolver should be cleared to address(0)"
        );

        // Verify CANNOT_SET_RESOLVER fuse was burned
        (, uint32 newFuses, ) = nameWrapper.getData(testTokenId);
        assertTrue(
            (newFuses & CANNOT_SET_RESOLVER) != 0,
            "CANNOT_SET_RESOLVER should be burnt after migration"
        );
    }

    function test_freezeName_preserves_resolver_when_fuse_already_set() public {
        // Setup locked name with CANNOT_SET_RESOLVER fuse already set
        uint32 lockedFuses = CANNOT_UNWRAP | IS_DOT_ETH | CANNOT_SET_RESOLVER;
        nameWrapper.setFuseData(testTokenId, lockedFuses, uint64(block.timestamp + 86400));

        // Set an initial resolver on the name
        address initialResolver = address(0x8888);
        nameWrapper.setInitialResolver(testTokenId, initialResolver);

        // Verify resolver is initially set
        assertEq(
            nameWrapper.getResolver(testTokenId),
            initialResolver,
            "Initial resolver should be set"
        );

        // Prepare migration data
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                name: NameCoder.ethName(testLabel),
                owner: user,
                subregistry: address(0), // Will be created by migratedRegistryFactory
                resolver: address(0xABCD),
                roleBitmap: RegistryRolesLib.ROLE_SET_RESOLVER,
                expires: uint64(block.timestamp + 86400)
            }),
            toL1: true,
            salt: uint256(keccak256(abi.encodePacked(testLabel, block.timestamp)))
        });

        bytes memory data = abi.encode(migrationData);

        // Call onERC1155Received
        vm.prank(address(nameWrapper));
        migrationController.onERC1155Received(owner, owner, testTokenId, 1, data);

        // Verify resolver remains unchanged (since fuse was already set)
        assertEq(
            nameWrapper.getResolver(testTokenId),
            initialResolver,
            "Resolver should be preserved when fuse already set"
        );

        // Verify CANNOT_SET_RESOLVER fuse remains set
        (, uint32 newFuses, ) = nameWrapper.getData(testTokenId);
        assertTrue(
            (newFuses & CANNOT_SET_RESOLVER) != 0,
            "CANNOT_SET_RESOLVER should remain burnt"
        );
    }
    */
}
