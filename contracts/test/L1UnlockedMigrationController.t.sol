// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// solhint-disable private-vars-leading-underscore, one-contract-per-file

import {Test, Vm, console} from "forge-std/Test.sol";

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

import {BridgeEncoder} from "./../src/common/BridgeEncoder.sol";
import {LibEACBaseRoles} from "./../src/common/EnhancedAccessControl.sol";
import {UnauthorizedCaller} from "./../src/common/Errors.sol";
import {LibBridgeRoles} from "./../src/common/IBridge.sol";
import {LibRegistryRoles} from "./../src/common/LibRegistryRoles.sol";
import {NameUtils} from "./../src/common/NameUtils.sol";
import {PermissionedRegistry} from "./../src/common/PermissionedRegistry.sol";
import {RegistryDatastore} from "./../src/common/RegistryDatastore.sol";
import {SimpleRegistryMetadata} from "./../src/common/SimpleRegistryMetadata.sol";
import {TransferData, MigrationData} from "./../src/common/TransferData.sol";
import {L1BridgeController} from "./../src/L1/L1BridgeController.sol";
import {
    L1UnlockedMigrationController,
    ETH_NODE
} from "./../src/L1/L1UnlockedMigrationController.sol";
import {MockL1Bridge} from "./../src/mocks/MockL1Bridge.sol";

/// forge-config: default.fuzz.runs = 8
contract TestL1UnlockedMigrationController is Test, ERC1155Holder, ERC721Holder {
    RegistryDatastore datastore;
    PermissionedRegistry ethRegistry;

    ENSRegistry ensV1;
    BaseRegistrarImplementation ethRegistrarV1;
    NameWrapper nameWrapper;

    MockL1Bridge bridge;
    L1BridgeController bridgeController;
    L1UnlockedMigrationController controller;

    MockERC721 dummy721;
    MockERC1155 dummy1155;

    address user = makeAddr("user");
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

        // setup V1
        ensV1 = new ENSRegistry();
        ethRegistrarV1 = new BaseRegistrarImplementation(ensV1, ETH_NODE);
        _claimNodes(NameCoder.encode("eth"), 0, address(ethRegistrarV1));
        _claimNodes(NameCoder.encode("addr.reverse"), 0, address(this));
        ethRegistrarV1.addController(address(this));
        nameWrapper = new NameWrapper(ensV1, ethRegistrarV1, IMetadataService(address(0)));

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

    // fake ReverseClaimer
    function claim(address) external pure returns (bytes32) {}

    function _claimNodes(bytes memory name, uint256 offset, address owner) internal {
        bytes32 labelHash;
        (labelHash, offset, , ) = NameCoder.readLabel(name, offset, false);
        if (labelHash != bytes32(0)) {
            _claimNodes(name, offset, owner);
            ensV1.setSubnodeOwner(NameUtils.unhashedNamehash(name, offset), labelHash, owner);
        }
    }

    function _registerUnwrapped(
        string memory label
    ) internal returns (bytes memory name, uint256 tokenId) {
        name = NameUtils.dnsEncodeEthLabel(label);
        tokenId = uint256(keccak256(bytes(label)));
        ethRegistrarV1.register(tokenId, user, 86400);
        assertEq(ethRegistrarV1.ownerOf(tokenId), user, "owner");
    }

    function _registerWrappedETH2LD(
        string memory label,
        uint32 ownerFuses
    ) internal returns (bytes memory name, uint256 tokenId) {
        (name, tokenId) = _registerUnwrapped(label);
        address owner = ethRegistrarV1.ownerOf(tokenId);
        vm.startPrank(owner);
        ethRegistrarV1.setApprovalForAll(address(nameWrapper), true);
        nameWrapper.wrapETH2LD(label, owner, uint16(ownerFuses), address(0));
        vm.stopPrank();
        tokenId = uint256(NameCoder.namehash(ETH_NODE, bytes32(tokenId)));
        assertEq(nameWrapper.ownerOf(tokenId), user, "owner");
    }

    function _wrapChild(
        uint256 parentTokenId,
        string memory label,
        uint32 fuses
    ) internal returns (bytes memory name, uint256 tokenId) {
        bytes memory parentName = nameWrapper.names(bytes32(parentTokenId));
        (address owner, uint64 expiry, ) = nameWrapper.getData(parentTokenId);
        name = NameUtils.appendLabel(parentName, label);
        vm.prank(owner);
        tokenId = uint256(
            nameWrapper.setSubnodeOwner(bytes32(parentTokenId), label, owner, fuses, expiry)
        );
    }

    function _wrapName(
        string memory domain,
        uint32 fuses
    ) internal returns (bytes memory name, uint256 tokenId) {
        name = NameCoder.encode(domain);
        _claimNodes(name, 0, address(this));
        (bytes32 labelHash, uint256 offset, , ) = NameCoder.readLabel(name, 0, false);
        bytes32 parentNode = NameUtils.unhashedNamehash(name, offset);
        ensV1.setApprovalForAll(address(nameWrapper), true);
        nameWrapper.wrap(name, user, address(0));
        tokenId = uint256(NameCoder.namehash(parentNode, labelHash));
        vm.prank(user);
        nameWrapper.setFuses(bytes32(tokenId), uint16(fuses));
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

    function _createMigrationData(
        bytes memory name,
        bool toL1
    ) internal view returns (MigrationData memory) {
        return
            MigrationData({
                transferData: TransferData({
                    dnsEncodedName: name,
                    owner: address(0x1111),
                    subregistry: address(0x2222),
                    resolver: address(0x3333),
                    roleBitmap: 0,
                    expires: 0 // not part of migration
                }),
                toL1: toL1,
                salt: uint256(keccak256(abi.encodePacked(name, block.timestamp)))
            });
    }

    function _assertMigration(Vm.Log[] memory logs, bytes memory name, bool toL1) internal view {
        string memory title = toL1 ? "NameEjectedToL1" : "NameBridgedToL2";
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(bridge) &&
                logs[i].topics[0] == keccak256("NameBridgedToL2(bytes)")
            ) {
                bytes memory message = abi.decode(logs[i].data, (bytes));
                TransferData memory td = BridgeEncoder.decodeEjection(message);
                if (keccak256(td.dnsEncodedName) == keccak256(name)) {
                    assertFalse(
                        toL1,
                        string.concat("unexpected ", title, ": ", NameCoder.decode(name))
                    );
                    found = true;
                    break;
                }
            } else if (
                logs[i].emitter == address(bridgeController) &&
                logs[i].topics[0] == keccak256("NameEjectedToL1(bytes,uint256)")
            ) {
                bytes memory dnsEncodedName = abi.decode(logs[i].data, (bytes));
                if (keccak256(dnsEncodedName) == keccak256(name)) {
                    assertTrue(
                        toL1,
                        string.concat("unexpected ", title, ": ", NameCoder.decode(name))
                    );
                    found = true;
                    break;
                }
            }
        }
        if (found) {
            // assume: if we got here, the name was ETH2LD
            (bytes32 labelHash, ) = NameCoder.readLabel(name, 0);
            assertEq(ethRegistrarV1.ownerOf(uint256(labelHash)), address(controller), "burned");
        } else {
            revert(string.concat("expected ", title, ": ", NameCoder.decode(name)));
        }
    }

    function test_constructor() external view {
        assertEq(address(controller.ETH_REGISTRY_V1()), address(ethRegistrarV1), "ethRegistrarV1");
        assertEq(address(controller.NAME_WRAPPER()), address(nameWrapper), "nameWrapper");
        assertEq(address(controller.BRIDGE()), address(bridge), "bridge");
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
    // Quirks
    ////////////////////////////////////////////////////////////////////////

    function test_Revert_nameWrapper_wrapRoot() external {
        vm.expectRevert(_encodeError("readLabel: Index out of bounds"));
        nameWrapper.wrap(hex"00", address(1), address(0));
    }

    function test_Revert_ethRegistrarV1_ownerOfUnregistered() external {
        vm.expectRevert();
        ethRegistrarV1.ownerOf(0);
    }

    ////////////////////////////////////////////////////////////////////////
    // Unwrapped
    ////////////////////////////////////////////////////////////////////////

    function test_migrateETH2LD_unwrapped_viaReceiver(bool toL1) external {
        (bytes memory name, uint256 tokenId) = _registerUnwrapped("test");
        vm.recordLogs();
        vm.prank(user);
        ethRegistrarV1.safeTransferFrom(
            user,
            address(controller),
            tokenId,
            abi.encode(_createMigrationData(name, toL1))
        );
        _assertMigration(vm.getRecordedLogs(), name, toL1);
        assertEq(ethRegistrarV1.ownerOf(tokenId), address(controller), "burned");
    }
    function test_migrateETH2LD_unwrapped_viaApproval(bool toL1) external {
        (bytes memory name, uint256 tokenId) = _registerUnwrapped("test");
        vm.recordLogs();
        vm.startPrank(user);
        ethRegistrarV1.setApprovalForAll(address(controller), true);
        controller.migrateETH2LD(_createMigrationData(name, toL1));
        vm.stopPrank();
        _assertMigration(vm.getRecordedLogs(), name, toL1);
        assertEq(ethRegistrarV1.ownerOf(tokenId), address(controller), "burned");
    }

    function test_Revert_migrateETH2LD_unwrapped_unauthorizedCaller() external {
        uint256 tokenId = dummy721.mint(user);
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedCaller.selector, address(dummy721)));
        vm.prank(user);
        dummy721.safeTransferFrom(user, address(controller), tokenId);
    }

    function test_Revert_migrateETH2LD_unwrapped_viaReceiver_notOperator(bool toL1) external {
        (bytes memory name, uint256 tokenId) = _registerUnwrapped("test");
        vm.expectRevert(_encodeError("ERC721: caller is not token owner or approved"));
        vm.prank(user2);
        ethRegistrarV1.safeTransferFrom(
            user,
            address(controller),
            tokenId,
            abi.encode(_createMigrationData(name, toL1))
        );
    }
    function test_Revert_migrateETH2LD_unwrapped_viaApproval_notOperator(bool toL1) external {
        (bytes memory name, ) = _registerUnwrapped("test");
        vm.expectRevert(_encodeError("ERC721: caller is not token owner or approved"));
        vm.prank(user2);
        controller.migrateETH2LD(_createMigrationData(name, toL1));
    }

    function test_Revert_migrateETH2LD_unwrapped_viaReceiver_nodeMismatch(bool toL1) external {
        (bytes memory name, ) = _registerUnwrapped("test");
        (, uint256 tokenId) = _registerUnwrapped("test2");
        vm.expectRevert(_encodeError(controller.ERROR_NODE_MISMATCH()));
        vm.prank(user);
        ethRegistrarV1.safeTransferFrom(
            user,
            address(controller),
            tokenId,
            abi.encode(_createMigrationData(name, toL1))
        );
    }

    function test_Revert_migrateETH2LD_unwrapped_viaReceiver_unregistered(bool toL1) external {
        (bytes memory name, ) = _registerUnwrapped("test");
        vm.expectRevert(); // ownerOf empty revert
        vm.prank(user);
        ethRegistrarV1.safeTransferFrom(
            user,
            address(controller),
            0,
            abi.encode(_createMigrationData(name, toL1))
        );
    }
    function test_Revert_migrateETH2LD_unwrapped_viaApproval_unregistered(bool toL1) external {
        vm.startPrank(user);
        ethRegistrarV1.setApprovalForAll(address(controller), true);
        vm.expectRevert(); // ownerOf empty revert
        controller.migrateETH2LD(_createMigrationData(NameCoder.encode("abc"), toL1));
        vm.stopPrank();
    }

    function test_Revert_migrateETH2LD_unwrapped_viaReceiver_invalidName(bool toL1) external {
        (, uint256 tokenId) = _registerUnwrapped("test");
        bytes memory name = hex"ff"; // invalid
        vm.expectRevert(abi.encodeWithSelector(NameCoder.DNSDecodingFailed.selector, name));
        vm.prank(user);
        ethRegistrarV1.safeTransferFrom(
            user,
            address(controller),
            tokenId,
            abi.encode(_createMigrationData(name, toL1))
        );
    }
    function test_Revert_migrateETH2LD_unwrapped_viaApproval_invalidName(bool toL1) external {
        bytes memory name = hex"ff"; // invalid
        vm.startPrank(user);
        ethRegistrarV1.setApprovalForAll(address(controller), true);
        vm.expectRevert(abi.encodeWithSelector(NameCoder.DNSDecodingFailed.selector, name));
        controller.migrateETH2LD(_createMigrationData(name, toL1));
        vm.stopPrank();
    }

    ////////////////////////////////////////////////////////////////////////
    // Wrapped
    ////////////////////////////////////////////////////////////////////////

    function test_migrateETH2LD_wrapped_single_unlocked_viaReceiver(bool toL1) public {
        (bytes memory name, uint256 tokenId) = _registerWrappedETH2LD("test", CAN_DO_EVERYTHING);
        vm.recordLogs();
        vm.prank(user);
        nameWrapper.safeTransferFrom(
            user,
            address(controller),
            tokenId,
            1,
            abi.encode(_createMigrationData(name, toL1))
        );
        _assertMigration(vm.getRecordedLogs(), name, toL1);
    }
    function test_migrateETH2LD_wrapped_single_unlocked_viaApproval(bool toL1) public {
        (bytes memory name, ) = _registerWrappedETH2LD("test", CAN_DO_EVERYTHING);
        vm.startPrank(user);
        nameWrapper.setApprovalForAll(address(controller), true);
        vm.recordLogs();
        controller.migrateETH2LD(_createMigrationData(name, toL1));
        vm.stopPrank();
        _assertMigration(vm.getRecordedLogs(), name, toL1);
    }

    function test_migrateETH2LD_batchWrapped_unlocked_viaReceiver(
        bool toL1_1,
        bool toL1_2
    ) external {
        (bytes memory name1, uint256 tokenId1) = _registerWrappedETH2LD("test1", CAN_DO_EVERYTHING);
        (bytes memory name2, uint256 tokenId2) = _registerWrappedETH2LD("test2", CAN_DO_EVERYTHING);
        uint256[] memory ids = new uint256[](2);
        ids[0] = tokenId1;
        ids[1] = tokenId2;
        MigrationData[] memory mds = new MigrationData[](2);
        mds[0] = _createMigrationData(name1, toL1_1);
        mds[1] = _createMigrationData(name2, toL1_2);
        vm.recordLogs();
        vm.prank(user);
        nameWrapper.safeBatchTransferFrom(
            user,
            address(controller),
            ids,
            _unitAmounts(ids.length),
            abi.encode(mds)
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertMigration(logs, name1, toL1_1);
        _assertMigration(logs, name2, toL1_2);
    }

    function test_migrateETH2LD_unwrappedAndWrapped_viaApproval(bool toL1_1, bool toL1_2) external {
        (bytes memory name1, ) = _registerUnwrapped("test1");
        (bytes memory name2, ) = _registerWrappedETH2LD("test2", CAN_DO_EVERYTHING);
        MigrationData[] memory mds = new MigrationData[](2);
        mds[0] = _createMigrationData(name1, toL1_1);
        mds[1] = _createMigrationData(name2, toL1_2);
        vm.startPrank(user);
        ethRegistrarV1.setApprovalForAll(address(controller), true);
        nameWrapper.setApprovalForAll(address(controller), true);
        vm.recordLogs();
        controller.migrateETH2LD(mds);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _assertMigration(logs, name1, toL1_1);
        _assertMigration(logs, name2, toL1_2);
    }

    function test_Revert_migrateETH2LD_wrapped_single_locked_viaApproval(bool toL1) external {
        (bytes memory name, ) = _registerWrappedETH2LD("test", CANNOT_UNWRAP);
        vm.startPrank(user);
        nameWrapper.setApprovalForAll(address(controller), true);
        vm.expectRevert(
            abi.encodeWithSelector(L1UnlockedMigrationController.NameIsLocked.selector, name)
        );
        controller.migrateETH2LD(_createMigrationData(name, toL1));
        vm.stopPrank();
    }
    function test_Revert_migrateETH2LD_wrapped_single_locked_viaReceiver(bool toL1) external {
        (bytes memory name, uint256 tokenId) = _registerWrappedETH2LD("test", CANNOT_UNWRAP);
        vm.expectRevert(_encodeError(controller.ERROR_NAME_IS_LOCKED()));
        vm.prank(user);
        nameWrapper.safeTransferFrom(
            user,
            address(controller),
            tokenId,
            1,
            abi.encode(_createMigrationData(name, toL1))
        );
    }

    function test_Revert_migrateETH2LD_batchWrapped_locked_viaReceiver(bool toL1) public {
        (bytes memory name1, uint256 tokenId1) = _registerWrappedETH2LD("test1", CANNOT_UNWRAP);
        (bytes memory name2, uint256 tokenId2) = _registerWrappedETH2LD("test2", CANNOT_UNWRAP);
        uint256[] memory ids = new uint256[](2);
        ids[0] = tokenId1;
        ids[1] = tokenId2;
        MigrationData[] memory mds = new MigrationData[](2);
        mds[0] = _createMigrationData(name1, toL1);
        mds[1] = _createMigrationData(name2, toL1);
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
        (bytes memory name1, uint256 tokenId1) = _registerWrappedETH2LD("test1", CANNOT_UNWRAP);
        (bytes memory name2, uint256 tokenId2) = _registerWrappedETH2LD("test2", CANNOT_UNWRAP);
        uint256[] memory ids = new uint256[](2);
        ids[0] = tokenId1;
        ids[1] = tokenId2;
        MigrationData[] memory mds = new MigrationData[](2);
        mds[0] = _createMigrationData(name1, toL1);
        mds[1] = _createMigrationData(name2, toL1);
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
        (, uint256 parentTokenId) = _registerWrappedETH2LD("test", CAN_DO_EVERYTHING);
        (bytes memory name, uint256 tokenId) = _wrapChild(parentTokenId, "sub", CAN_DO_EVERYTHING);
        vm.expectRevert(_encodeError(controller.ERROR_NAME_NOT_ETH2LD()));
        vm.prank(user);
        nameWrapper.safeTransferFrom(
            user,
            address(controller),
            tokenId,
            1,
            abi.encode(_createMigrationData(name, toL1))
        );
    }
    function test_Revert_migrateETH2LD_wrapped_3LD_viaApproval(bool toL1) external {
        (, uint256 parentTokenId) = _registerWrappedETH2LD("test", CANNOT_UNWRAP);
        (bytes memory name, ) = _wrapChild(parentTokenId, "sub", CAN_DO_EVERYTHING);
        vm.startPrank(user);
        nameWrapper.setApprovalForAll(address(controller), true);
        vm.expectRevert(
            abi.encodeWithSelector(L1UnlockedMigrationController.NameNotETH2LD.selector, name)
        );
        controller.migrateETH2LD(_createMigrationData(name, toL1));
        vm.stopPrank();
    }

    function test_Revert_migrateETH2LD_wrapped_comTLD_viaReceiver(bool toL1) external {
        (bytes memory name, uint256 tokenId) = _wrapName("test.com", CAN_DO_EVERYTHING);
        vm.expectRevert(_encodeError(controller.ERROR_NAME_NOT_ETH2LD()));
        vm.prank(user);
        nameWrapper.safeTransferFrom(
            user,
            address(controller),
            tokenId,
            1,
            abi.encode(_createMigrationData(name, toL1))
        );
    }
    function test_Revert_migrateETH2LD_wrapped_comTLD_viaApproval(bool toL1) external {
        (bytes memory name, ) = _wrapName("test.com", CAN_DO_EVERYTHING);
        vm.startPrank(user);
        nameWrapper.setApprovalForAll(address(controller), true);
        vm.expectRevert(
            abi.encodeWithSelector(L1UnlockedMigrationController.NameNotETH2LD.selector, name)
        );
        controller.migrateETH2LD(_createMigrationData(name, toL1));
        vm.stopPrank();
    }

    function test_Revert_migrateETH2LD_wrapped_single_unlocked_viaReceiver_notOperator(
        bool toL1
    ) external {
        (bytes memory name, uint256 tokenId) = _registerWrappedETH2LD("test", CAN_DO_EVERYTHING);
        vm.expectRevert(_encodeError("ERC1155: caller is not owner nor approved"));
        vm.prank(user2);
        nameWrapper.safeTransferFrom(
            user,
            address(controller),
            tokenId,
            1,
            abi.encode(_createMigrationData(name, toL1))
        );
    }
    function test_Revert_migrateETH2LD_wrapped_single_unlocked_viaApproval_notOperator(
        bool toL1
    ) external {
        (bytes memory name, ) = _registerWrappedETH2LD("test", CAN_DO_EVERYTHING);
        vm.expectRevert(_encodeError("ERC1155: caller is not owner nor approved"));
        vm.prank(user2);
        controller.migrateETH2LD(_createMigrationData(name, toL1));
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
