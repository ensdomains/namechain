// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

import {EnhancedAccessControl} from "../access-control/EnhancedAccessControl.sol";
import {UnauthorizedCaller} from "../CommonErrors.sol";
import {IPermissionedRegistry} from "../registry/interfaces/IPermissionedRegistry.sol";
import {LibLabel} from "../utils/LibLabel.sol";
import {IBridge} from "./interfaces/IBridge.sol";
import {BridgeRolesLib} from "./libraries/BridgeRolesLib.sol";
import {TransferData} from "./types/TransferData.sol";

/**
 * @title EjectionController
 * @dev Base contract for the ejection controllers.
 */
abstract contract EjectionController is IERC1155Receiver, ERC165, EnhancedAccessControl {
    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    IPermissionedRegistry public immutable REGISTRY;

    IBridge public immutable BRIDGE;

    ////////////////////////////////////////////////////////////////////////
    // Storage
    ////////////////////////////////////////////////////////////////////////

    mapping(address owner => bool invalid) public isInvalidTransferOwner;

    ////////////////////////////////////////////////////////////////////////
    // Events
    ////////////////////////////////////////////////////////////////////////

    event NameInjected(uint256 indexed tokenId, string label);

    event NameEjected(uint256 indexed tokenId, string label);

    event TransferOwnerValidityChanged(address owner, bool invalid);

    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    error TokenLabelMismatch(uint256 tokenId, string label);
    error InvalidTokenAmount(uint256 tokenId); // IERC1155Errors.ERC1155InsufficientBalance?

    error InvalidTransferOwner(address owner);

    ////////////////////////////////////////////////////////////////////////
    // Modifiers
    ////////////////////////////////////////////////////////////////////////

    modifier onlyRegistry() {
        if (msg.sender != address(REGISTRY)) {
            revert UnauthorizedCaller(msg.sender);
        }
        _;
    }

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(IPermissionedRegistry registry, IBridge bridge) {
        REGISTRY = registry;
        BRIDGE = bridge;

        isInvalidTransferOwner[address(0)] = true;

        // Grant admin roles to the deployer so they can manage bridge roles
        _grantRoles(ROOT_RESOURCE, BridgeRolesLib.ROLE_EJECTOR_ADMIN, msg.sender, true);
    }

    /// @inheritdoc IERC165
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165, EnhancedAccessControl, IERC165) returns (bool) {
        return
            interfaceId == type(EjectionController).interfaceId ||
            interfaceId == type(IERC1155Receiver).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    function setInvalidTransferOwner(
        address owner,
        bool invalid
    ) external onlyRootRoles(BridgeRolesLib.ROLE_EJECTOR_ADMIN) {
        isInvalidTransferOwner[owner] = invalid;
        emit TransferOwnerValidityChanged(owner, invalid);
    }

    // TODO: do we need to check amount?
    // underlying is ERC1155Singleton so no?
    // L1BridgeController burns
    // L2BridgeController operates
    // both fail if not owned

    /// Implements ERC1155Receiver.onERC1155Received
    function onERC1155Received(
        address /*operator*/,
        address /* from */,
        uint256 id,
        uint256 /*amount*/,
        bytes calldata data
    ) public virtual onlyRegistry returns (bytes4) {
        TransferData memory td = abi.decode(data, (TransferData));
        _checkEjection(id, td);
        TransferData[] memory tds = new TransferData[](1);
        tds[0] = td;
        _onEject(tds);
        return this.onERC1155Received.selector;
    }

    /// Implements ERC1155Receiver.onERC1155BatchReceived
    function onERC1155BatchReceived(
        address /*operator*/,
        address /* from */,
        uint256[] calldata ids,
        uint256[] calldata /*amounts*/,
        bytes calldata data
    ) public virtual onlyRegistry returns (bytes4) {
        TransferData[] memory tds = abi.decode(data, (TransferData[]));
        if (ids.length != tds.length) {
            revert IERC1155Errors.ERC1155InvalidArrayLength(ids.length, tds.length);
        }
        for (uint256 i; i < tds.length; ++i) {
            _checkEjection(ids[i], tds[i]);
        }
        _onEject(tds);
        return this.onERC1155BatchReceived.selector;
    }

    ////////////////////////////////////////////////////////////////////////
    // Internal Functions
    ////////////////////////////////////////////////////////////////////////

    /// @dev Called when names are ejected.
    ///
    /// @param tds Array of transfer data items
    function _onEject(TransferData[] memory tds) internal virtual;

    /// @dev Asserts that the DNS-encoded name matches the token ID.
    ///
    /// @param tokenId The token ID to check
    /// @param td The `TransferData` to check.
    function _checkEjection(uint256 tokenId, TransferData memory td) internal view {
        if (LibLabel.getCanonicalId(tokenId) != LibLabel.labelToCanonicalId(td.label)) {
            revert TokenLabelMismatch(tokenId, td.label);
        }
        if (isInvalidTransferOwner[td.owner]) {
            revert InvalidTransferOwner(td.owner);
        }
    }
}
