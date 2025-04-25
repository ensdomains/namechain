// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ITokenObserver} from "./ITokenObserver.sol";  
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IPermissionedRegistry} from "./IPermissionedRegistry.sol";

/**
 * @title EjectionController
 * @dev Base contract for the ejection controllers.
 */
abstract contract EjectionController is ITokenObserver, IERC1155Receiver {
    IPermissionedRegistry public immutable registry;

    struct TransferData {
        string label;
        address newOwner;
        address newSubregistry;
        address newResolver;
        uint64 newExpires;
    }

    constructor(IPermissionedRegistry _registry) {
        registry = _registry;
    }

    /**
     * Implements ERC165.supportsInterface
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(EjectionController).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId;
    }

    /**
     * Implements ERC1155Receiver.onERC1155Received
     */
    function onERC1155Received(address /*operator*/, address /*from*/, uint256 tokenId, uint256 /*amount*/, bytes calldata data) external virtual returns (bytes4) {
        TransferData memory transferData = abi.decode(data, (TransferData));
        _onEject(tokenId, transferData);
        return this.onERC1155Received.selector;
    }

    /**
     * Implements ERC1155Receiver.onERC1155BatchReceived
     */
    function onERC1155BatchReceived(address /*operator*/, address /*from*/, uint256[] memory tokenIds, uint256[] memory /*amounts*/, bytes calldata data) external virtual returns (bytes4) {
        TransferData[] memory transferDataArray = abi.decode(data, (TransferData[]));
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            TransferData memory transferData = transferDataArray[i];
            _onEject(tokenIds[i], transferData);
        }
        return this.onERC1155BatchReceived.selector;
    }

    /**
     * Implements ITokenObserver.onRenew
     */
    function onRenew(uint256 tokenId, uint64 expires, address renewedBy) external virtual;

    /**
     * Implements ITokenObserver.onRelinquish
     */
    function onRelinquish(uint256 tokenId, address relinquishedBy) external virtual;

    // Internal functions

    /**
     * @dev Called when a name is ejected.
     *
     * @param tokenId The token ID of the name being ejected
     * @param transferData The transfer data containing label, l1Owner, l1Subregistry, l1Resolver, and expires
     */
    function _onEject(uint256 tokenId, TransferData memory transferData) internal virtual;
}
