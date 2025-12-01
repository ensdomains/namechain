// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import {EnhancedAccessControl} from "../access-control/EnhancedAccessControl.sol";
import {UnauthorizedCaller} from "../CommonErrors.sol";
import {HCAEquivalence} from "../hca/HCAEquivalence.sol";
import {IHCAFactoryBasic} from "../hca/interfaces/IHCAFactoryBasic.sol";
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
    // Events
    ////////////////////////////////////////////////////////////////////////

    event NameEjectedToL1(bytes dnsEncodedName, uint256 indexed tokenId);

    event NameEjectedToL2(bytes dnsEncodedName, uint256 indexed tokenId);

    ////////////////////////////////////////////////////////////////////////
    // Errors
    ////////////////////////////////////////////////////////////////////////

    error InvalidLabel(uint256 tokenId, string label);

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

    constructor(
        IPermissionedRegistry registry_,
        IBridge bridge_
    ) HCAEquivalence(IHCAFactoryBasic(address(0))) {
        REGISTRY = registry_;
        BRIDGE = bridge_;

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

    /// Implements ERC1155Receiver.onERC1155Received
    function onERC1155Received(
        address /*operator*/,
        address /* from */,
        uint256 tokenId,
        uint256 /*amount*/,
        bytes calldata data
    ) external virtual onlyRegistry returns (bytes4) {
        _processEjection(tokenId, data);
        return this.onERC1155Received.selector;
    }

    /// Implements ERC1155Receiver.onERC1155BatchReceived
    function onERC1155BatchReceived(
        address /*operator*/,
        address /* from */,
        uint256[] calldata tokenIds,
        uint256[] calldata /*amounts*/,
        bytes calldata data
    ) external virtual onlyRegistry returns (bytes4) {
        TransferData[] memory transferDataArray = abi.decode(data, (TransferData[]));

        _onEject(tokenIds, transferDataArray);

        return this.onERC1155BatchReceived.selector;
    }

    ////////////////////////////////////////////////////////////////////////
    // Internal Functions
    ////////////////////////////////////////////////////////////////////////

    /// @dev Core ejection logic for single token transfers
    ///      Can be called by derived classes that need to customize onERC1155Received behavior
    function _processEjection(uint256 tokenId, bytes calldata data) internal {
        TransferData memory transferData = abi.decode(data, (TransferData));

        TransferData[] memory transferDataArray = new TransferData[](1);
        transferDataArray[0] = transferData;

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        _onEject(tokenIds, transferDataArray);
    }

    /// @dev Called when names are ejected.
    ///
    /// @param tokenIds Array of token IDs of the names being ejected
    /// @param transferDataArray Array of transfer data items
    function _onEject(
        uint256[] memory tokenIds,
        TransferData[] memory transferDataArray
    ) internal virtual;

    /// @dev Asserts that the DNS-encoded name matches the token ID.
    ///
    /// @param tokenId The token ID to check
    /// @param dnsEncodedName The DNS-encoded name to check
    function _assertTokenIdMatchesLabel(
        uint256 tokenId,
        bytes memory dnsEncodedName
    ) internal pure {
        string memory label = NameCoder.firstLabel(dnsEncodedName);
        if (LibLabel.labelToCanonicalId(label) != LibLabel.getCanonicalId(tokenId)) {
            revert InvalidLabel(tokenId, label);
        }
    }
}
