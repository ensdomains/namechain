// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IPermissionedRegistry} from "./IPermissionedRegistry.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {TransferData} from "./TransferData.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {NameUtils} from "./NameUtils.sol";
import {IBridge} from "./IBridge.sol";

/**
 * @title EjectionController
 * @dev Base contract for the ejection controllers.
 */
abstract contract EjectionController is IERC1155Receiver, ERC165 {
    error UnauthorizedCaller(address caller);
    error InvalidLabel(uint256 tokenId, string label);

    event NameEjectedToL1(bytes dnsEncodedName, uint256 tokenId);
    event NameEjectedToL2(bytes dnsEncodedName, uint256 tokenId);

    IPermissionedRegistry public immutable registry;
    IBridge public immutable bridge;

    modifier onlyBridge() {
        if (msg.sender != address(bridge)) {
            revert UnauthorizedCaller(msg.sender);
        }
        _;
    }

    constructor(IPermissionedRegistry _registry, IBridge _bridge) {
        registry = _registry;
        bridge = _bridge;
    }

    /**
     * Implements ERC165.supportsInterface
     */
    function supportsInterface(bytes4 interfaceId) public virtual view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(EjectionController).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * Implements ERC1155Receiver.onERC1155Received
     */
    function onERC1155Received(address /*operator*/, address from, uint256 tokenId, uint256 /*amount*/, bytes calldata data) external virtual returns (bytes4) {
        if (msg.sender != address(registry)) {
            revert UnauthorizedCaller(msg.sender);
        }

        TransferData memory transferData = abi.decode(data, (TransferData));
        
        TransferData[] memory transferDataArray = new TransferData[](1);
        transferDataArray[0] = transferData;
        
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        _onEject(tokenIds, transferDataArray, address(from) == address(0));

        return this.onERC1155Received.selector;
    }

    /**
     * Implements ERC1155Receiver.onERC1155BatchReceived
     */
    function onERC1155BatchReceived(address /*operator*/, address from, uint256[] memory tokenIds, uint256[] memory /*amounts*/, bytes calldata data) external virtual returns (bytes4) {
        if (msg.sender != address(registry)) {
            revert UnauthorizedCaller(msg.sender);
        }

        TransferData[] memory transferDataArray = abi.decode(data, (TransferData[]));
        
        _onEject(tokenIds, transferDataArray, address(from) == address(0));

        return this.onERC1155BatchReceived.selector;
    }

    // Internal functions

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
     * @param isMint Whether the names are being minted or ejected
     */
    function _onEject(uint256[] memory tokenIds, TransferData[] memory transferDataArray, bool isMint) internal virtual;
}
