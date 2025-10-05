// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// solhint-disable private-vars-leading-underscore, one-contract-per-file

import {Test, Vm} from "forge-std/Test.sol";

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {CANNOT_UNWRAP, CAN_DO_EVERYTHING} from "@ens/contracts/wrapper/INameWrapper.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {BridgeEncoder} from "../src/common/BridgeEncoder.sol";
import {UnauthorizedCaller} from "../src/common/Errors.sol";
import {LibBridgeRoles} from "../src/common/IBridge.sol";
import {LibRegistryRoles} from "../src/common/LibRegistryRoles.sol";
import {NameUtils} from "../src/common/NameUtils.sol";
import {PermissionedRegistry, IRegistryDatastore} from "../src/common/PermissionedRegistry.sol";
import {L1BridgeController} from "../src/L1/L1BridgeController.sol";
import {
    UnlockedMigrationController,
    TransferData,
    MigrationErrors
} from "../src/L1/UnlockedMigrationController.sol";
import {MockL1Bridge} from "../src/mocks/MockL1Bridge.sol";
import {NameWrapperFixture} from "./fixtures/NameWrapperFixture.sol";
import {ETHRegistryMixin} from "./fixtures/ETHRegistryMixin.sol";

/// forge-config: default.fuzz.runs = 8
contract TestUnlockedMigrationController is NameWrapperFixture, ETHRegistryMixin {
    MockL1Bridge bridge;
    L1BridgeController bridgeController;
    UnlockedMigrationController migrationController;

    MockERC721 dummy721;
    MockERC1155 dummy1155;

    address user2 = makeAddr("user2");

    function setUp() public {
        deployNameWrapper();
        deployETHRegistry();

        dummy721 = new MockERC721();
        dummy1155 = new MockERC1155();

        bridge = new MockL1Bridge();

        bridgeController = new L1BridgeController(ethRegistry, bridge);

        ethRegistry.grantRootRoles(
            LibRegistryRoles.ROLE_REGISTRAR |
                LibRegistryRoles.ROLE_RENEW |
                LibRegistryRoles.ROLE_BURN,
            address(bridgeController)
        );

        migrationController = new UnlockedMigrationController(nameWrapper, bridgeController);

        bridgeController.grantRootRoles(LibBridgeRoles.ROLE_EJECTOR, address(migrationController));
    }

    function _makeData(
        bytes memory name,
        bool toL1
    ) internal view returns (UnlockedMigrationController.Data memory) {
        return
            UnlockedMigrationController.Data({
                toL1: toL1,
                label: NameUtils.firstLabel(name),
                owner: user,
                resolver: address(1),
                subregistry: address(2),
                roleBitmap: 0,
                salt: uint256(keccak256(abi.encode(name, block.timestamp)))
            });
    }

    function _assertMigrations(
        Vm.Log[] memory logs,
        UnlockedMigrationController.Data[] memory mds
    ) internal view {
        for (uint256 i; i < mds.length; ++i) {
            _assertMigration(logs, mds[i]);
        }
    }
    function _assertMigration(
        Vm.Log[] memory logs,
        UnlockedMigrationController.Data memory md
    ) internal view {
        bytes32 testHash = keccak256(NameUtils.appendETH(md.label));
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(bridge) &&
                logs[i].topics[0] == keccak256("MessageSent(bytes)")
            ) {
                bytes memory message = abi.decode(logs[i].data, (bytes));
                TransferData memory td = BridgeEncoder.decodeEjection(message);
                if (keccak256(td.name) == testHash) {
                    assertFalse(md.toL1, string.concat("expected L2: ", md.label));
                    found = true;
                    break;
                }
            } else if (
                logs[i].emitter == address(bridgeController) &&
                logs[i].topics[0] == keccak256("NameEjectedToL1(bytes,uint256)")
            ) {
                bytes memory name = abi.decode(logs[i].data, (bytes));
                if (keccak256(name) == testHash) {
                    assertTrue(md.toL1, string.concat("expected L1: ", md.label));
                    found = true;
                    break;
                }
            }
        }
        if (found) {
            uint256 tokenIdV1 = uint256(keccak256(bytes(md.label)));
            assertEq(ethRegistrarV1.ownerOf(tokenIdV1), address(migrationController), "burned");
            if (md.toL1) {
                (uint256 tokenId, IRegistryDatastore.Entry memory entry) = ethRegistry.getNameData(
                    md.label
                );
                assertEq(ethRegistry.ownerOf(tokenId), md.owner, "owner");
                assertEq(entry.resolver, md.resolver, "resolver");
                assertEq(entry.subregistry, md.subregistry, "subregistry");
                assertEq(
                    ethRegistry.getExpiry(tokenId),
                    ethRegistrarV1.nameExpires(tokenIdV1),
                    "expiry"
                );
            } else {
                // mock bridging
            }
        } else {
            revert(string.concat("expected transfer: ", md.label));
        }
    }

    function test_constructor() external view {
        assertEq(
            address(migrationController.ETH_REGISTRAR_V1()),
            address(ethRegistrarV1),
            "ethRegistrarV1"
        );
        assertEq(address(migrationController.NAME_WRAPPER()), address(nameWrapper), "nameWrapper");
        assertEq(
            address(migrationController.L1_BRIDGE_CONTROLLER()),
            address(bridgeController),
            "bridgeController"
        );
        assertEq(migrationController.owner(), address(this), "owner");
    }

    function test_supportsInterface() external view {
        assertTrue(migrationController.supportsInterface(type(IERC165).interfaceId), "IERC165");
        assertTrue(
            migrationController.supportsInterface(type(IERC721Receiver).interfaceId),
            "IERC721Receiver"
        );
        assertTrue(
            migrationController.supportsInterface(type(IERC1155Receiver).interfaceId),
            "IERC1155Receiver"
        );
    }

    ////////////////////////////////////////////////////////////////////////
    // Unwrapped
    ////////////////////////////////////////////////////////////////////////

    function test_Revert_migrate_unwrapped_transferWrongNFT() external {
        uint256 tokenId = dummy721.mint(user);
        vm.expectRevert(
            abi.encodeWithSignature("Error(string)", MigrationErrors.ERROR_ONLY_ETH_REGISTRAR)
        );
        vm.prank(user);
        dummy721.safeTransferFrom(user, address(migrationController), tokenId);
    }

    function test_Revert_migrate_unwrapped_transfer() external {
        (, uint256 tokenId) = registerUnwrapped("test");
        vm.expectRevert(
            abi.encodeWithSignature("Error(string)", MigrationErrors.ERROR_UNEXPECTED_TRANSFER)
        );
        vm.prank(user);
        ethRegistrarV1.safeTransferFrom(user, address(migrationController), tokenId, "");
    }

    function test_Revert_migrate_unwrapped_notOperator(bool toL1) external {
        (bytes memory name, ) = registerUnwrapped("test");
        vm.expectRevert(
            abi.encodeWithSignature(
                "Error(string)",
                "ERC721: caller is not token owner or approved"
            )
        );
        vm.prank(user2);
        migrationController.migrate(_makeData(name, toL1));
    }

    function test_Revert_migrate_unwrapped_unregistered(bool toL1) external {
        vm.startPrank(user);
        ethRegistrarV1.setApprovalForAll(address(migrationController), true);
        vm.expectRevert(bytes("")); // null revert from 721 transfer
        migrationController.migrate(_makeData(NameUtils.appendETH("test"), toL1));
        vm.stopPrank();
    }

    ////////////////////////////////////////////////////////////////////////
    // Wrapped
    ////////////////////////////////////////////////////////////////////////

    function test_Revert_migrate_1wrapped_transferWrongNFT() external {
        uint256 tokenId = dummy1155.mint(user);
        vm.expectRevert(
            abi.encodeWithSignature("Error(string)", MigrationErrors.ERROR_ONLY_NAME_WRAPPER)
        );
        vm.prank(user);
        dummy1155.safeTransferFrom(user, address(migrationController), tokenId, 1, "");
    }

    function test_Revert_migrate_1wrapped_transfer() external {
        (, uint256 tokenId) = registerWrappedETH2LD("test", CAN_DO_EVERYTHING);
        vm.expectRevert(
            abi.encodeWithSignature("Error(string)", MigrationErrors.ERROR_UNEXPECTED_TRANSFER)
        );
        vm.prank(user);
        nameWrapper.safeTransferFrom(user, address(migrationController), tokenId, 1, "");
    }

    function test_Revert_migrate_2wrapped_transfer() external {
        (, uint256 tokenId1) = registerWrappedETH2LD("test1", CAN_DO_EVERYTHING);
        (, uint256 tokenId2) = registerWrappedETH2LD("test2", CAN_DO_EVERYTHING);
        uint256[] memory ids = new uint256[](2);
        ids[0] = tokenId1;
        ids[1] = tokenId2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;
        vm.expectRevert(
            abi.encodeWithSignature("Error(string)", MigrationErrors.ERROR_UNEXPECTED_TRANSFER)
        );
        vm.prank(user);
        nameWrapper.safeBatchTransferFrom(user, address(migrationController), ids, amounts, "");
    }

    function test_Revert_migrate_1wrapped_locked(bool toL1) external {
        (bytes memory name, ) = registerWrappedETH2LD("test", CANNOT_UNWRAP);
        vm.startPrank(user);
        nameWrapper.setApprovalForAll(address(migrationController), true);
        vm.expectRevert(abi.encodeWithSelector(MigrationErrors.NameIsLocked.selector, name));
        migrationController.migrate(_makeData(name, toL1));
        vm.stopPrank();
    }

    function test_Revert_migrate_2wrapped_locked(bool[2] memory toL1) external {
        (bytes memory name1, uint256 tokenId1) = registerWrappedETH2LD("test1", CANNOT_UNWRAP);
        (bytes memory name2, uint256 tokenId2) = registerWrappedETH2LD("test2", CANNOT_UNWRAP);
        uint256[] memory ids = new uint256[](2);
        ids[0] = tokenId1;
        ids[1] = tokenId2;
        UnlockedMigrationController.Data[] memory mds = new UnlockedMigrationController.Data[](2);
        mds[0] = _makeData(name1, toL1[0]);
        mds[1] = _makeData(name2, toL1[1]);
        vm.startPrank(user);
        nameWrapper.setApprovalForAll(address(migrationController), true);
        vm.expectRevert(
            abi.encodeWithSelector(MigrationErrors.NameIsLocked.selector, name1) // first name revert
        );
        migrationController.migrate(mds);
        vm.stopPrank();
    }

    function test_Revert_migrate_1wrapped_3LD(bool toL1) external {
        (, uint256 parentTokenId) = registerWrappedETH2LD("test", CANNOT_UNWRAP);
        (bytes memory name, ) = createWrappedChild(parentTokenId, "sub", CAN_DO_EVERYTHING);
        vm.startPrank(user);
        nameWrapper.setApprovalForAll(address(migrationController), true);
        vm.expectRevert(bytes("")); // null revert from 721 transfer
        migrationController.migrate(_makeData(name, toL1));
        vm.stopPrank();
    }

    function test_Revert_migrate_1wrapped_comTLD(bool toL1) external {
        (bytes memory name, ) = createWrappedName("test.com", CAN_DO_EVERYTHING);
        vm.startPrank(user);
        nameWrapper.setApprovalForAll(address(migrationController), true);
        vm.expectRevert(bytes("")); // null revert from 721 transfer
        migrationController.migrate(_makeData(name, toL1));
        vm.stopPrank();
    }

    function test_Revert_migrate_1wrapped_notOperator(bool toL1) external {
        (bytes memory name, ) = registerWrappedETH2LD("test", CAN_DO_EVERYTHING);
        vm.expectRevert(
            abi.encodeWithSignature("Error(string)", "ERC1155: caller is not owner nor approved")
        );
        vm.prank(user2);
        migrationController.migrate(_makeData(name, toL1));
    }

    ////////////////////////////////////////////////////////////////////////
    // Migrations
    ////////////////////////////////////////////////////////////////////////

    function test_Revert_migrate_emptyLabel() external {
        vm.startPrank(user);
        ethRegistrarV1.setApprovalForAll(address(migrationController), true);
        UnlockedMigrationController.Data memory md;
        md.label = "";
        vm.expectRevert(bytes("")); // null revert from 721 transfer
        migrationController.migrate(md);
        vm.stopPrank();
    }

    function test_Revert_migrate_invalidLabel() external {
        vm.startPrank(user);
        ethRegistrarV1.setApprovalForAll(address(migrationController), true);
        UnlockedMigrationController.Data memory md;
        md.label = new string(256);
        vm.expectRevert(bytes("")); // null revert from 721 transfer
        migrationController.migrate(md);
        vm.stopPrank();
    }

    function test_migrate_unwrapped(bool toL1) external {
        (bytes memory name, ) = registerUnwrapped("test");
        UnlockedMigrationController.Data memory md = _makeData(name, toL1);
        vm.recordLogs();
        vm.startPrank(user);
        ethRegistrarV1.setApprovalForAll(address(migrationController), true);
        migrationController.migrate(md);
        vm.stopPrank();
        _assertMigration(vm.getRecordedLogs(), md);
    }

    function test_migrate_1wrapped(bool toL1) external {
        (bytes memory name, ) = registerWrappedETH2LD("test", CAN_DO_EVERYTHING);
        UnlockedMigrationController.Data memory md = _makeData(name, toL1);
        vm.recordLogs();
        vm.startPrank(user);
        nameWrapper.setApprovalForAll(address(migrationController), true);
        migrationController.migrate(md);
        vm.stopPrank();
        _assertMigration(vm.getRecordedLogs(), md);
    }

    function _test_migrateETH2LD(uint256 unwrapped, uint256 wrapped) internal {
        UnlockedMigrationController.Data[] memory mds = new UnlockedMigrationController.Data[](
            unwrapped + wrapped
        );
        for (uint256 i; i < unwrapped; ++i) {
            (bytes memory name, ) = registerUnwrapped(string(abi.encodePacked("u", 0x30 + i)));
            mds[i] = _makeData(name, (i & 1) != 0);
        }
        for (uint256 i; i < wrapped; ++i) {
            (bytes memory name, ) = registerWrappedETH2LD(
                string(abi.encodePacked("w", 0x30 + i)),
                CAN_DO_EVERYTHING
            );
            mds[unwrapped + i] = _makeData(name, (i & 1) != 0);
        }
        vm.startPrank(user);
        ethRegistrarV1.setApprovalForAll(address(migrationController), true);
        nameWrapper.setApprovalForAll(address(migrationController), true);
        vm.recordLogs();
        migrationController.migrate(mds);
        _assertMigrations(vm.getRecordedLogs(), mds);
    }

    function test_migrate_0unwrapped_0wrapped() external {
        _test_migrateETH2LD(0, 0);
    }
    function test_migrate_0unwrapped_1wrapped() external {
        _test_migrateETH2LD(0, 1);
    }
    function test_migrate_1unwrapped_0wrapped() external {
        _test_migrateETH2LD(1, 0);
    }
    function test_migrate_0unwrapped_2wrapped() external {
        _test_migrateETH2LD(0, 2);
    }
    function test_migrate_1unwrapped_1wrapped() external {
        _test_migrateETH2LD(1, 1);
    }
    function test_migrate_2unwrapped_0wrapped() external {
        _test_migrateETH2LD(2, 0);
    }
    function test_migrate_1unwrapped_2wrapped() external {
        _test_migrateETH2LD(1, 2);
    }
    function test_migrate_2unwrapped_1wrapped() external {
        _test_migrateETH2LD(2, 1);
    }
    function test_migrate_2unwrapped_2wrapped() external {
        _test_migrateETH2LD(2, 2);
    }
}

contract MockERC721 is ERC721 {
    uint256 _id;
    constructor() ERC721("", "") {}
    function mint(address to) external returns (uint256) {
        _mint(to, _id);
        return _id++;
    }
}

contract MockERC1155 is ERC1155 {
    uint256 _id;
    constructor() ERC1155("") {}
    function mint(address to) external returns (uint256) {
        _mint(to, _id, 1, "");
        return _id++;
    }
}
