// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IPermissionedRegistry} from "./IPermissionedRegistry.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {TransferData} from "./TransferData.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {NameUtils} from "./NameUtils.sol";
import {IBridge, LibBridgeRoles} from "./IBridge.sol";
import {EnhancedAccessControl, LibEACBaseRoles} from "./EnhancedAccessControl.sol";

/**
 * @title EjectionController
 * @dev Base contract for the ejection controllers.
 */
abstract contract EjectionController is IERC1155Receiver, ERC165, EnhancedAccessControl {
    error UnauthorizedCaller(address caller);
    error InvalidLabel(uint256 tokenId, string label);

    event NameEjectedToL1(bytes dnsEncodedName, uint256 tokenId);
    event NameEjectedToL2(bytes dnsEncodedName, uint256 tokenId);

    IPermissionedRegistry public immutable registry;
    IBridge public immutable bridge;

    modifier onlyRegistry() {
        if (msg.sender != address(registry)) {
            revert UnauthorizedCaller(msg.sender);
        }
        _;
    }

    constructor(IPermissionedRegistry _registry, IBridge _bridge) {
        registry = _registry;
        bridge = _bridge;
        
        // Grant admin roles to the deployer so they can manage bridge roles
        _grantRoles(ROOT_RESOURCE, LibBridgeRoles.ROLE_EJECTOR_ADMIN, _msgSender(), true);
    }

    /**
     * Implements ERC165.supportsInterface
     */
    function supportsInterface(bytes4 interfaceId) public virtual view override(ERC165, EnhancedAccessControl, IERC165) returns (bool) {
        return interfaceId == type(EjectionController).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * Implements ERC1155Receiver.onERC1155Received
     */
    function onERC1155Received(address /*operator*/, address /* from */, uint256 tokenId, uint256 /*amount*/, bytes calldata data) external virtual onlyRegistry returns (bytes4) {
        _processEjection(tokenId, data);
        return this.onERC1155Received.selector;
    }

    /**
     * Implements ERC1155Receiver.onERC1155BatchReceived
     */
    function onERC1155BatchReceived(address /*operator*/, address /* from */, uint256[] memory tokenIds, uint256[] memory /*amounts*/, bytes calldata data) external virtual onlyRegistry returns (bytes4) { 
        TransferData[] memory transferDataArray = abi.decode(data, (TransferData[]));
        
        _onEject(tokenIds, transferDataArray);

        return this.onERC1155BatchReceived.selector;
    }

    // Internal functions

    /**
     * @dev Core ejection logic for single token transfers
     * Can be called by derived classes that need to customize onERC1155Received behavior
     */
    function _processEjection(uint256 tokenId, bytes calldata data) internal {
        TransferData memory transferData = abi.decode(data, (TransferData));
        
        TransferData[] memory transferDataArray = new TransferData[](1);
        transferDataArray[0] = transferData;
        
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        _onEject(tokenIds, transferDataArray);
    }

    /**
     * @dev Asserts that the label matches the token ID.
     *
     * @param tokenId The token ID to check
     * @param label The label to check
     */
    function _assertTokenIdMatchesLabel(uint256 tokenId, string memory label) internal pure {
        if (NameUtils.labelToCanonicalId(label) != NameUtils.getCanonicalId(tokenId)) {
            revert InvalidLabel(tokenId, label);
        }
    }

    /**
     * @dev Called when names are ejected.
     *
     * @param tokenIds Array of token IDs of the names being ejected
     * @param transferDataArray Array of transfer data items
     */
    function _onEject(uint256[] memory tokenIds, TransferData[] memory transferDataArray) internal virtual;
}
