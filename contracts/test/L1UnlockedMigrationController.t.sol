// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// solhint-disable private-vars-leading-underscore, one-contract-per-file

import {Test, Vm} from "forge-std/Test.sol";

import {
    BaseRegistrarImplementation
} from "@ens/contracts/ethregistrar/BaseRegistrarImplementation.sol";
import {ENSRegistry} from "@ens/contracts/registry/ENSRegistry.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {
    NameWrapper,
    IMetadataService,
    CANNOT_UNWRAP,
    CAN_DO_EVERYTHING
} from "@ens/contracts/wrapper/NameWrapper.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {BridgeEncoder} from "../src/common/BridgeEncoder.sol";
import {LibEACBaseRoles} from "../src/common/EnhancedAccessControl.sol";
import {UnauthorizedCaller} from "../src/common/Errors.sol";
import {LibBridgeRoles} from "../src/common/IBridge.sol";
import {LibRegistryRoles} from "../src/common/LibRegistryRoles.sol";
import {NameUtils} from "../src/common/NameUtils.sol";
import {PermissionedRegistry, IRegistryDatastore} from "../src/common/PermissionedRegistry.sol";
import {RegistryDatastore} from "../src/common/RegistryDatastore.sol";
import {SimpleRegistryMetadata} from "../src/common/SimpleRegistryMetadata.sol";
import {TransferData, MigrationData} from "../src/common/TransferData.sol";
import {L1BridgeController} from "../src/L1/L1BridgeController.sol";
import {L1UnlockedMigrationController} from "../src/L1/L1UnlockedMigrationController.sol";
import {MockL1Bridge} from "../src/mocks/MockL1Bridge.sol";
import {TestV1Mixin} from "./fixtures/TestV1Mixin.sol";

/// forge-config: default.fuzz.runs = 8
contract TestL1UnlockedMigrationController is TestV1Mixin, ERC1155Holder, ERC721Holder {
    RegistryDatastore datastore;
    PermissionedRegistry ethRegistry;

    MockL1Bridge bridge;
    L1BridgeController bridgeController;
    L1UnlockedMigrationController controller;

    MockERC721 dummy721;
    MockERC1155 dummy1155;

    address user2 = makeAddr("user2");

    function setUp() public {
        datastore = new RegistryDatastore();
        ethRegistry = new PermissionedRegistry(
            datastore,
            new SimpleRegistryMetadata(),
            address(this),
            LibEACBaseRoles.ALL_ROLES
        );

        dummy721 = new MockERC721();
        dummy1155 = new MockERC1155();

        deployV1();

        // Deploy mock bridge
        bridge = new MockL1Bridge();

        // Deploy REAL bridgeController with real dependencies
        bridgeController = new L1BridgeController(ethRegistry, bridge);

        // Grant necessary roles to the ejection controller
        ethRegistry.grantRootRoles(
            LibRegistryRoles.ROLE_REGISTRAR |
                LibRegistryRoles.ROLE_RENEW |
                LibRegistryRoles.ROLE_BURN,
            address(bridgeController)
        );

        // Deploy migration controller with the REAL ejection controller
        controller = new L1UnlockedMigrationController(
            ethRegistrarV1,
            nameWrapper,
            bridgeController
        );

        // Grant ROLE_EJECTOR to the migration controller so it can call the ejection controller
        bridgeController.grantRootRoles(LibBridgeRoles.ROLE_EJECTOR, address(controller));

        vm.warp(ethRegistrarV1.GRACE_PERIOD() + 1); // avoid timestamp issues
    }

    function _unitAmounts(uint256 n) internal pure returns (uint256[] memory amounts) {
        amounts = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            amounts[i] = 1;
        }
    }

    function _encodeError(string memory message) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("Error(string)", message);
    }

    function _migrationData(
        bytes memory name,
        bool toL1
    ) internal view returns (MigrationData memory) {
        return
            MigrationData({
                transferData: TransferData({
                    name: name,
                    owner: user,
                    subregistry: address(0x2222),
                    resolver: address(0x3333),
                    roleBitmap: 0,
                    expiry: 0 // set by controller
                }),
                toL1: toL1,
                salt: uint256(keccak256(abi.encodePacked(name, block.timestamp)))
            });
    }

    function _assertMigrations(Vm.Log[] memory logs, MigrationData[] memory mds) internal view {
        for (uint256 i; i < mds.length; ++i) {
            _assertMigration(logs, mds[i]);
        }
    }
    function _assertMigration(Vm.Log[] memory logs, MigrationData memory md) internal view {
        string memory title = md.toL1 ? "NameEjectedToL1" : "NameBridgedToL2";
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(bridge) &&
                logs[i].topics[0] == keccak256("NameBridgedToL2(bytes)")
            ) {
                bytes memory message = abi.decode(logs[i].data, (bytes));
                TransferData memory td = BridgeEncoder.decodeEjection(message);
                if (keccak256(td.name) == keccak256(md.transferData.name)) {
                    assertFalse(md.toL1, string.concat("unexpected ", title));
                    found = true;
                    break;
                }
            } else if (
                logs[i].emitter == address(bridgeController) &&
                logs[i].topics[0] == keccak256("NameEjectedToL1(bytes,uint256)")
            ) {
                bytes memory name = abi.decode(logs[i].data, (bytes));
                if (keccak256(name) == keccak256(md.transferData.name)) {
                    assertTrue(md.toL1, string.concat("unexpected ", title));
                    found = true;
                    break;
                }
            }
        }
        if (found) {
            // assume ETH2LD
            string memory label = NameUtils.firstLabel(md.transferData.name);
            uint256 tokenIdV1 = uint256(keccak256(bytes(label)));
            assertEq(ethRegistrarV1.ownerOf(tokenIdV1), address(controller), "burned");
            if (md.toL1) {
                (uint256 tokenId, IRegistryDatastore.Entry memory entry) = ethRegistry.getNameData(
                    label
                );
                assertEq(ethRegistry.ownerOf(tokenId), md.transferData.owner, "owner");
                assertEq(entry.resolver, md.transferData.resolver, "resolver");
                assertEq(entry.subregistry, md.transferData.subregistry, "subregistry");
                assertEq(
                    ethRegistry.getExpiry(tokenId),
                    ethRegistrarV1.nameExpires(tokenIdV1),
                    "expiry"
                );
            } else {
                // mock bridging
            }
        } else {
            revert(string.concat("expected ", title));
        }
    }

    function test_constructor() external view {
        assertEq(address(controller.ETH_REGISTRY_V1()), address(ethRegistrarV1), "ethRegistrarV1");
        assertEq(address(controller.NAME_WRAPPER()), address(nameWrapper), "nameWrapper");
        assertEq(
            address(controller.L1_BRIDGE_CONTROLLER()),
            address(bridgeController),
            "bridgeController"
        );
        assertEq(controller.owner(), address(this), "owner");
    }

    function test_supportsInterface() external view {
        assertTrue(controller.supportsInterface(type(IERC165).interfaceId), "IERC165");
        assertTrue(
            controller.supportsInterface(type(IERC721Receiver).interfaceId),
            "IERC721Receiver"
        );
        assertTrue(
            controller.supportsInterface(type(IERC1155Receiver).interfaceId),
            "IERC1155Receiver"
        );
    }

    ////////////////////////////////////////////////////////////////////////
    // Unwrapped
    ////////////////////////////////////////////////////////////////////////

    function test_migrateETH2LD_unwrapped_viaReceiver(bool toL1) external {
        (bytes memory name, uint256 tokenId) = registerUnwrapped("test");
        MigrationData memory md = _migrationData(name, toL1);
        vm.recordLogs();
        vm.prank(user);
        ethRegistrarV1.safeTransferFrom(user, address(controller), tokenId, abi.encode(md));
        _assertMigration(vm.getRecordedLogs(), md);
    }
    function test_migrateETH2LD_unwrapped_viaApproval(bool toL1) external {
        (bytes memory name, ) = registerUnwrapped("test");
        MigrationData memory md = _migrationData(name, toL1);
        vm.recordLogs();
        vm.startPrank(user);
        ethRegistrarV1.setApprovalForAll(address(controller), true);
        controller.migrateETH2LD(md);
        vm.stopPrank();
        _assertMigration(vm.getRecordedLogs(), md);
    }

    function test_Revert_migrateETH2LD_unwrapped_unauthorizedCaller() external {
        uint256 tokenId = dummy721.mint(user);
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector, address(dummy721)));
        vm.prank(user);
        dummy721.safeTransferFrom(user, address(controller), tokenId);
    }

    function test_Revert_migrateETH2LD_unwrapped_viaReceiver_notOperator(bool toL1) external {
        (bytes memory name, uint256 tokenId) = registerUnwrapped("test");
        vm.expectRevert(_encodeError("ERC721: caller is not token owner or approved"));
        vm.prank(user2);
        ethRegistrarV1.safeTransferFrom(
            user,
            address(controller),
            tokenId,
            abi.encode(_migrationData(name, toL1))
        );
    }
    function test_Revert_migrateETH2LD_unwrapped_viaApproval_notOperator(bool toL1) external {
        (bytes memory name, ) = registerUnwrapped("test");
        vm.expectRevert(_encodeError("ERC721: caller is not token owner or approved"));
        vm.prank(user2);
        controller.migrateETH2LD(_migrationData(name, toL1));
    }

    function test_Revert_migrateETH2LD_unwrapped_viaReceiver_nodeMismatch(bool toL1) external {
        (bytes memory name, ) = registerUnwrapped("test");
        (, uint256 tokenId) = registerUnwrapped("test2");
        vm.expectRevert(_encodeError(controller.ERROR_NODE_MISMATCH()));
        vm.prank(user);
        ethRegistrarV1.safeTransferFrom(
            user,
            address(controller),
            tokenId,
            abi.encode(_migrationData(name, toL1))
        );
    }

    function test_Revert_migrateETH2LD_unwrapped_viaReceiver_unregistered(bool toL1) external {
        (bytes memory name, ) = registerUnwrapped("test");
        vm.expectRevert(); // ownerOf empty revert
        vm.prank(user);
        ethRegistrarV1.safeTransferFrom(
            user,
            address(controller),
            0,
            abi.encode(_migrationData(name, toL1))
        );
    }
    function test_Revert_migrateETH2LD_unwrapped_viaApproval_unregistered(bool toL1) external {
        vm.startPrank(user);
        ethRegistrarV1.setApprovalForAll(address(controller), true);
        vm.expectRevert(); // ownerOf empty revert
        controller.migrateETH2LD(_migrationData(NameCoder.encode("abc"), toL1));
        vm.stopPrank();
    }

    function test_Revert_migrateETH2LD_unwrapped_viaReceiver_invalidName(bool toL1) external {
        (, uint256 tokenId) = registerUnwrapped("test");
        bytes memory name = hex"ff"; // invalid
        vm.expectRevert(abi.encodeWithSelector(NameCoder.DNSDecodingFailed.selector, name));
        vm.prank(user);
        ethRegistrarV1.safeTransferFrom(
            user,
            address(controller),
            tokenId,
            abi.encode(_migrationData(name, toL1))
        );
    }
    function test_Revert_migrateETH2LD_unwrapped_viaApproval_invalidName(bool toL1) external {
        bytes memory name = hex"ff"; // invalid
        vm.startPrank(user);
        ethRegistrarV1.setApprovalForAll(address(controller), true);
        vm.expectRevert(abi.encodeWithSelector(NameCoder.DNSDecodingFailed.selector, name));
        controller.migrateETH2LD(_migrationData(name, toL1));
        vm.stopPrank();
    }

    ////////////////////////////////////////////////////////////////////////
    // Wrapped
    ////////////////////////////////////////////////////////////////////////

    function test_migrateETH2LD_wrapped_single_unlocked_viaReceiver(bool toL1) public {
        (bytes memory name, uint256 tokenId) = registerWrappedETH2LD("test", CAN_DO_EVERYTHING);
        MigrationData memory md = _migrationData(name, toL1);
        vm.recordLogs();
        vm.prank(user);
        nameWrapper.safeTransferFrom(user, address(controller), tokenId, 1, abi.encode(md));
        _assertMigration(vm.getRecordedLogs(), md);
    }
    function test_migrateETH2LD_wrapped_single_unlocked_viaApproval(bool toL1) public {
        (bytes memory name, ) = registerWrappedETH2LD("test", CAN_DO_EVERYTHING);
        MigrationData memory md = _migrationData(name, toL1);
        vm.startPrank(user);
        nameWrapper.setApprovalForAll(address(controller), true);
        vm.recordLogs();
        controller.migrateETH2LD(md);
        vm.stopPrank();
        _assertMigration(vm.getRecordedLogs(), md);
    }

    function test_migrateETH2LD_batchWrapped_unlocked_viaReceiver(
        bool toL1_1,
        bool toL1_2
    ) external {
        (bytes memory name1, uint256 tokenId1) = registerWrappedETH2LD("test1", CAN_DO_EVERYTHING);
        (bytes memory name2, uint256 tokenId2) = registerWrappedETH2LD("test2", CAN_DO_EVERYTHING);
        uint256[] memory ids = new uint256[](2);
        ids[0] = tokenId1;
        ids[1] = tokenId2;
        MigrationData[] memory mds = new MigrationData[](2);
        mds[0] = _migrationData(name1, toL1_1);
        mds[1] = _migrationData(name2, toL1_2);
        vm.recordLogs();
        vm.prank(user);
        nameWrapper.safeBatchTransferFrom(
            user,
            address(controller),
            ids,
            _unitAmounts(ids.length),
            abi.encode(mds)
        );
        _assertMigrations(vm.getRecordedLogs(), mds);
    }

    function test_migrateETH2LD_unwrappedAndWrapped_viaApproval(bool toL1_1, bool toL1_2) external {
        (bytes memory name1, ) = registerUnwrapped("test1");
        (bytes memory name2, ) = registerWrappedETH2LD("test2", CAN_DO_EVERYTHING);
        MigrationData[] memory mds = new MigrationData[](2);
        mds[0] = _migrationData(name1, toL1_1);
        mds[1] = _migrationData(name2, toL1_2);
        vm.startPrank(user);
        ethRegistrarV1.setApprovalForAll(address(controller), true);
        nameWrapper.setApprovalForAll(address(controller), true);
        vm.recordLogs();
        controller.migrateETH2LD(mds);
        _assertMigrations(vm.getRecordedLogs(), mds);
    }

    function test_Revert_migrateETH2LD_wrapped_single_locked_viaApproval(bool toL1) external {
        (bytes memory name, ) = registerWrappedETH2LD("test", CANNOT_UNWRAP);
        vm.startPrank(user);
        nameWrapper.setApprovalForAll(address(controller), true);
        vm.expectRevert(
            abi.encodeWithSelector(L1UnlockedMigrationController.NameIsLocked.selector, name)
        );
        controller.migrateETH2LD(_migrationData(name, toL1));
        vm.stopPrank();
    }
    function test_Revert_migrateETH2LD_wrapped_single_locked_viaReceiver(bool toL1) external {
        (bytes memory name, uint256 tokenId) = registerWrappedETH2LD("test", CANNOT_UNWRAP);
        vm.expectRevert(_encodeError(controller.ERROR_NAME_IS_LOCKED()));
        vm.prank(user);
        nameWrapper.safeTransferFrom(
            user,
            address(controller),
            tokenId,
            1,
            abi.encode(_migrationData(name, toL1))
        );
    }

    function test_Revert_migrateETH2LD_batchWrapped_locked_viaReceiver(bool toL1) public {
        (bytes memory name1, uint256 tokenId1) = registerWrappedETH2LD("test1", CANNOT_UNWRAP);
        (bytes memory name2, uint256 tokenId2) = registerWrappedETH2LD("test2", CANNOT_UNWRAP);
        uint256[] memory ids = new uint256[](2);
        ids[0] = tokenId1;
        ids[1] = tokenId2;
        MigrationData[] memory mds = new MigrationData[](2);
        mds[0] = _migrationData(name1, toL1);
        mds[1] = _migrationData(name2, toL1);
        vm.expectRevert(_encodeError(controller.ERROR_NAME_IS_LOCKED()));
        vm.prank(user);
        nameWrapper.safeBatchTransferFrom(
            user,
            address(controller),
            ids,
            _unitAmounts(ids.length),
            abi.encode(mds)
        );
    }
    function test_Revert_migrateETH2LD_batchWrapped_locked_viaApproval(bool toL1) public {
        (bytes memory name1, uint256 tokenId1) = registerWrappedETH2LD("test1", CANNOT_UNWRAP);
        (bytes memory name2, uint256 tokenId2) = registerWrappedETH2LD("test2", CANNOT_UNWRAP);
        uint256[] memory ids = new uint256[](2);
        ids[0] = tokenId1;
        ids[1] = tokenId2;
        MigrationData[] memory mds = new MigrationData[](2);
        mds[0] = _migrationData(name1, toL1);
        mds[1] = _migrationData(name2, toL1);
        vm.startPrank(user);
        nameWrapper.setApprovalForAll(address(controller), true);
        vm.expectRevert(
            abi.encodeWithSelector(L1UnlockedMigrationController.NameIsLocked.selector, name1) // first name revert
        );
        controller.migrateETH2LD(mds);
        vm.stopPrank();
    }

    function test_Revert_migrateETH2LD_wrapped_unauthorizedCaller() external {
        uint256 tokenId = dummy1155.mint(user);
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector, address(dummy1155)));
        vm.prank(user);
        dummy1155.safeTransferFrom(user, address(controller), tokenId, 1, "");
    }

    function test_Revert_migrateETH2LD_wrapped_3LD_viaReceiver(bool toL1) external {
        (, uint256 parentTokenId) = registerWrappedETH2LD("test", CAN_DO_EVERYTHING);
        (bytes memory name, uint256 tokenId) = createWrappedChild(
            parentTokenId,
            "sub",
            CAN_DO_EVERYTHING
        );
        vm.expectRevert(_encodeError(controller.ERROR_NAME_NOT_ETH2LD()));
        vm.prank(user);
        nameWrapper.safeTransferFrom(
            user,
            address(controller),
            tokenId,
            1,
            abi.encode(_migrationData(name, toL1))
        );
    }
    function test_Revert_migrateETH2LD_wrapped_3LD_viaApproval(bool toL1) external {
        (, uint256 parentTokenId) = registerWrappedETH2LD("test", CANNOT_UNWRAP);
        (bytes memory name, ) = createWrappedChild(parentTokenId, "sub", CAN_DO_EVERYTHING);
        vm.startPrank(user);
        nameWrapper.setApprovalForAll(address(controller), true);
        vm.expectRevert(
            abi.encodeWithSelector(L1UnlockedMigrationController.NameNotETH2LD.selector, name)
        );
        controller.migrateETH2LD(_migrationData(name, toL1));
        vm.stopPrank();
    }

    function test_Revert_migrateETH2LD_wrapped_comTLD_viaReceiver(bool toL1) external {
        (bytes memory name, uint256 tokenId) = createWrappedName("test.com", CAN_DO_EVERYTHING);
        vm.expectRevert(_encodeError(controller.ERROR_NAME_NOT_ETH2LD()));
        vm.prank(user);
        nameWrapper.safeTransferFrom(
            user,
            address(controller),
            tokenId,
            1,
            abi.encode(_migrationData(name, toL1))
        );
    }
    function test_Revert_migrateETH2LD_wrapped_comTLD_viaApproval(bool toL1) external {
        (bytes memory name, ) = createWrappedName("test.com", CAN_DO_EVERYTHING);
        vm.startPrank(user);
        nameWrapper.setApprovalForAll(address(controller), true);
        vm.expectRevert(
            abi.encodeWithSelector(L1UnlockedMigrationController.NameNotETH2LD.selector, name)
        );
        controller.migrateETH2LD(_migrationData(name, toL1));
        vm.stopPrank();
    }

    function test_Revert_migrateETH2LD_wrapped_single_unlocked_viaReceiver_notOperator(
        bool toL1
    ) external {
        (bytes memory name, uint256 tokenId) = registerWrappedETH2LD("test", CAN_DO_EVERYTHING);
        vm.expectRevert(_encodeError("ERC1155: caller is not owner nor approved"));
        vm.prank(user2);
        nameWrapper.safeTransferFrom(
            user,
            address(controller),
            tokenId,
            1,
            abi.encode(_migrationData(name, toL1))
        );
    }
    function test_Revert_migrateETH2LD_wrapped_single_unlocked_viaApproval_notOperator(
        bool toL1
    ) external {
        (bytes memory name, ) = registerWrappedETH2LD("test", CAN_DO_EVERYTHING);
        vm.expectRevert(_encodeError("ERC1155: caller is not owner nor approved"));
        vm.prank(user2);
        controller.migrateETH2LD(_migrationData(name, toL1));
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
