// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {EnhancedAccessControl} from "../access-control/EnhancedAccessControl.sol";
import {UnauthorizedCaller} from "../CommonErrors.sol";
import {IPermissionedRegistry} from "../registry/interfaces/IPermissionedRegistry.sol";
import {LibLabel} from "../utils/LibLabel.sol";
import {BridgeEncoderLib} from "../../common/bridge/libraries/BridgeEncoderLib.sol";
import {IEnhancedAccessControl} from "../access-control/interfaces/IEnhancedAccessControl.sol";
import {EACBaseRolesLib} from "../access-control/libraries/EACBaseRolesLib.sol";

import {IBridge} from "./interfaces/IBridge.sol";
import {BridgeRolesLib} from "./libraries/BridgeRolesLib.sol";
import {TransferData, TRANSFER_DATA_MIN_SIZE} from "./types/TransferData.sol";

/// @notice Controller logic shared by both bridge controllers.
abstract contract AbstractBridgeController is IERC1155Receiver, EnhancedAccessControl {
    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    uint256 public constant MIN_TRANSFER_DURATION = 6 * 60 * 60; // 6 hours

    IPermissionedRegistry public immutable REGISTRY;

    IBridge public immutable BRIDGE;

    ////////////////////////////////////////////////////////////////////////
    // Events
    ////////////////////////////////////////////////////////////////////////

    event NameInjected(uint256 indexed tokenId, string label);
    event NameEjected(uint256 indexed tokenId, string label);

    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    error InvalidTransferData();
    error InvalidOwner(string label, address owner);
    error LabelTokenMismatch(string label, uint256 tokenId);
    error InvalidRoleBitmap(uint256 tokenId, uint256 roleBitmap);
    error InsufficientDuration(uint256 tokenId, uint64 expiry);

    ////////////////////////////////////////////////////////////////////////
    // Modifiers
    ////////////////////////////////////////////////////////////////////////

    modifier onlyRegistry() {
        if (msg.sender != address(REGISTRY)) {
            revert UnauthorizedCaller(msg.sender);
        }
        _;
    }

    modifier onlyDataSize(bytes calldata data, uint256 minSize) {
        if (data.length < minSize) {
            revert InvalidTransferData();
        }
        _;
    }

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(IPermissionedRegistry registry, IBridge bridge) {
        REGISTRY = registry;
        BRIDGE = bridge;

        // Grant admin roles to the deployer so they can manage bridge roles
        _grantRoles(ROOT_RESOURCE, BridgeRolesLib.ROLE_EJECTOR_ADMIN, msg.sender, true);
    }

    /// @inheritdoc IERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(EnhancedAccessControl, IERC165) returns (bool) {
        return
            interfaceId == type(AbstractBridgeController).interfaceId ||
            interfaceId == type(IERC1155Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    function completeEjection(
        TransferData calldata td
    ) external onlyRootRoles(BridgeRolesLib.ROLE_EJECTOR) returns (uint256 tokenId) {
        if (td.owner == address(this)) {
            revert InvalidOwner(td.label, td.owner);
        }
        tokenId = _inject(td);
        emit NameInjected(tokenId, td.label);
    }

    /// @inheritdoc IERC1155Receiver
    function onERC1155Received(
        address /*operator*/,
        address /* from */,
        uint256 id,
        uint256 /*amount*/,
        bytes calldata data
    ) public virtual onlyRegistry onlyDataSize(data, TRANSFER_DATA_MIN_SIZE) returns (bytes4) {
        TransferData memory td = abi.decode(data, (TransferData));
        _tryEjection(id, td);
        return this.onERC1155Received.selector;
    }

    /// @inheritdoc IERC1155Receiver
    function onERC1155BatchReceived(
        address /*operator*/,
        address /* from */,
        uint256[] calldata ids,
        uint256[] calldata /*amounts*/,
        bytes calldata data
    )
        public
        virtual
        onlyRegistry
        onlyDataSize(data, 64 + ids.length * TRANSFER_DATA_MIN_SIZE)
        returns (bytes4)
    {
        TransferData[] memory tds = abi.decode(data, (TransferData[]));
        if (ids.length != tds.length) {
            revert IERC1155Errors.ERC1155InvalidArrayLength(ids.length, tds.length);
        }
        for (uint256 i; i < tds.length; ++i) {
            _tryEjection(ids[i], tds[i]);
        }
        return this.onERC1155BatchReceived.selector;
    }

    ////////////////////////////////////////////////////////////////////////
    // Internal Functions
    ////////////////////////////////////////////////////////////////////////

    function _eject(uint256 tokenId, TransferData memory tds) internal virtual;

    function _inject(TransferData memory tds) internal virtual returns (uint256);

    function _tryEjection(uint256 tokenId, TransferData memory td) internal {
        if (LibLabel.getCanonicalId(tokenId) != LibLabel.labelToCanonicalId(td.label)) {
            revert LabelTokenMismatch(td.label, tokenId);
        }
        if (td.owner == address(0)) {
            revert InvalidOwner(td.label, td.owner);
        }
        _eject(tokenId, td);
        BRIDGE.sendMessage(BridgeEncoderLib.encodeEjection(td));
        emit NameEjected(tokenId, td.label);
    }
}
