// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {Test} from "forge-std/Test.sol";

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
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {
    ERC1155Holder,
    IERC1155Receiver
} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {IRegistry} from "~src/common/registry/interfaces/IRegistry.sol";
import {
    AbstractBridgeController,
    IEnhancedAccessControl,
    IBridge,
    IPermissionedRegistry,
    TransferData,
    TRANSFER_DATA_MIN_SIZE,
    EACBaseRolesLib,
    BridgeRolesLib,
    BridgeEncoderLib
} from "~src/common/bridge/AbstractBridgeController.sol";
import {MockBridgeBase} from "~test/mocks/MockBridgeBase.sol";
import {NameWrapperFixture} from "~test/fixtures/NameWrapperFixture.sol";
import {ETHFixtureMixin} from "~test/fixtures/ETHFixtureMixin.sol";

contract MockController is AbstractBridgeController {
    uint256 constant RING_SIZE = 256;
    mapping(uint256 => TransferData) transfers;
    uint256 public transferCount;

    constructor(
        IBridge bridge,
        IPermissionedRegistry registry
    ) AbstractBridgeController(bridge, registry) {}

    function lastTransfers(uint256 n) public view returns (TransferData[] memory tds) {
        require(n <= RING_SIZE, "ring");
        require(n <= transferCount, "count");
        tds = new TransferData[](n);
        uint256 start = transferCount + RING_SIZE - n;
        for (uint256 i; i < n; ++i) {
            tds[i] = transfers[(start + i) % RING_SIZE];
        }
    }

    function _eject(uint256 /*tokenId*/, TransferData memory td) internal override {
        td.expiry = 42; // make a modification
        transfers[transferCount++ % RING_SIZE] = td; // remember
    }

    function _inject(TransferData memory /*td*/) internal pure override returns (uint256) {
        return 0; // do nothing
    }
}

contract AbstractBridgeControllerTest is Test, ERC1155Holder, ETHFixtureMixin {
    ETHFixture fixture;
    MockBridgeBase bridge;
    MockController controller;

    address ejector = makeAddr("ejector");

    function setUp() external {
        fixture = deployETHFixture();
        bridge = new MockBridgeBase();
        controller = new MockController(bridge, fixture.ethRegistry);
        controller.grantRootRoles(BridgeRolesLib.ROLE_EJECTOR, ejector);
    }

    function test_supportsInterface() external view {
        assertTrue(
            controller.supportsInterface(type(AbstractBridgeController).interfaceId),
            "AbstractBridgeController"
        );
        assertTrue(
            controller.supportsInterface(type(IERC1155Receiver).interfaceId),
            "IERC1155Receiver"
        );
    }

    function test_TRANSFER_DATA_MIN_SIZE() external pure {
        TransferData memory td;
        assertEq(TRANSFER_DATA_MIN_SIZE, abi.encode(td).length);
    }

    function test_TRANSFER_DATA_MIN_SIZE_batch() external pure {
        TransferData[] memory tds = new TransferData[](3);
        assertEq(64 + tds.length * TRANSFER_DATA_MIN_SIZE, abi.encode(tds).length);
    }

    function test_completeEjection() external {
        TransferData memory td;
        td.label = "test";
        td.owner = address(1);
        vm.prank(ejector);
        vm.expectEmit(false, false, false, true);
        emit AbstractBridgeController.NameInjected(0, td.label);
        controller.completeEjection(td);
    }

    function test_completeEjection_notEjector() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                IEnhancedAccessControl.EACUnauthorizedAccountRoles.selector,
                0,
                BridgeRolesLib.ROLE_EJECTOR,
                address(this)
            )
        );
        TransferData memory td;
        controller.completeEjection(td);
    }

    function test_completeEjection_emptyLabel() external {
        TransferData memory td;
        vm.expectRevert(abi.encodeWithSelector(NameCoder.LabelIsEmpty.selector));
        vm.prank(ejector);
        controller.completeEjection(td);
    }

    function test_completeEjection_longLabel() external {
        TransferData memory td;
        td.label = new string(256);
        vm.expectRevert(abi.encodeWithSelector(NameCoder.LabelIsTooLong.selector, (td.label)));
        vm.prank(ejector);
        controller.completeEjection(td);
    }

    // function test_completeEjection_nullOwner() external {
    //     vm.prank(ejector);
    //     TransferData memory td;
    //     td.label = "test";
    //     controller.completeEjection(td);
    // }

    function test_completeEjection_ownerAsController() external {
        TransferData memory td;
        td.label = "test";
        td.owner = address(controller);
        vm.expectRevert(
            abi.encodeWithSelector(
                AbstractBridgeController.InvalidOwner.selector,
                td.label,
                td.owner
            )
        );
        vm.prank(ejector);
        controller.completeEjection(td);
    }

    function test_onERC1155Received() external {
        TransferData memory td = _randomTransferData();
        uint256 tokenId = _register(td);
        fixture.ethRegistry.safeTransferFrom(
            address(this),
            address(controller),
            tokenId,
            1,
            abi.encode(td)
        );
        assertEq(
            uint256(BridgeEncoderLib.getMessageType(bridge.lastMessage())),
            uint256(BridgeEncoderLib.MessageType.EJECTION),
            "type"
        );
        assertEq(
            abi.encode(controller.lastTransfers(1)[0]),
            abi.encode(BridgeEncoderLib.decodeEjection(bridge.lastMessage())),
            "data"
        );
    }

    function test_onERC1155Received_invalidTransferData() external {
        TransferData memory td = _randomTransferData();
        uint256 tokenId = _register(td);
        vm.expectRevert(
            abi.encodeWithSelector(AbstractBridgeController.InvalidTransferData.selector)
        );
        fixture.ethRegistry.safeTransferFrom(address(this), address(controller), tokenId, 1, "");
    }

    function test_onERC1155Received_invalidOwner() external {
        TransferData memory td = _randomTransferData();
        uint256 tokenId = _register(td);
        td.owner = address(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                AbstractBridgeController.InvalidOwner.selector,
                td.label,
                td.owner
            )
        );
        fixture.ethRegistry.safeTransferFrom(
            address(this),
            address(controller),
            tokenId,
            1,
            abi.encode(td)
        );
    }

    function test_onERC1155Received_wrongLabel() external {
        TransferData memory td = _randomTransferData();
        uint256 tokenId = _register(td);
        td.label = string.concat(td.label, "wrong");
        vm.expectRevert(
            abi.encodeWithSelector(
                AbstractBridgeController.LabelTokenMismatch.selector,
                td.label,
                tokenId
            )
        );
        fixture.ethRegistry.safeTransferFrom(
            address(this),
            address(controller),
            tokenId,
            1,
            abi.encode(td)
        );
    }

    function test_onERC1155BatchReceived(uint8 n) external {
        vm.assume(n < 10);
        uint256[] memory ids = new uint256[](n);
        uint256[] memory amounts = new uint256[](n);
        TransferData[] memory tds = new TransferData[](n);
        for (uint256 i; i < n; ++i) {
            TransferData memory td = _randomTransferData();
            ids[i] = _register(td);
            amounts[i] = 1;
            tds[i] = td;
        }
        fixture.ethRegistry.safeBatchTransferFrom(
            address(this),
            address(controller),
            ids,
            amounts,
            abi.encode(tds)
        );
        TransferData[] memory tds2 = controller.lastTransfers(n);
        bytes[] memory messages = bridge.lastMessages(n);
        for (uint256 i; i < n; ++i) {
            assertEq(
                uint256(BridgeEncoderLib.getMessageType(messages[i])),
                uint256(BridgeEncoderLib.MessageType.EJECTION),
                "type"
            );
            assertEq(
                abi.encode(tds2[i]),
                abi.encode(BridgeEncoderLib.decodeEjection(messages[i])),
                "data"
            );
        }
    }

    function _register(TransferData memory td) internal returns (uint256) {
        return
            fixture.ethRegistry.register(
                td.label,
                td.owner,
                td.subregistry,
                td.resolver,
                td.roleBitmap,
                td.expiry
            );
    }

    function _randomTransferData() internal returns (TransferData memory td) {
        td.label = string.concat("random", vm.toString(vm.randomUint()));
        td.owner = address(this);
        td.subregistry = IRegistry(vm.randomAddress());
        td.resolver = vm.randomAddress();
        td.roleBitmap = EACBaseRolesLib.ALL_ROLES;
        td.expiry = uint64(block.timestamp + 100);
    }
}
