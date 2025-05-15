// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IBaseRegistrar} from "@ens/contracts/ethregistrar/IBaseRegistrar.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title MigrationController
 * @dev Base contract for the v1-to-v2 migration controller.
 */
abstract contract MigrationController is IERC1155Receiver, IERC721Receiver, ERC165 {
    error CallerNotEthRegistryV1(address caller);
    error NotOwner(address owner);

    IBaseRegistrar public immutable ethRegistryV1;

    constructor(IBaseRegistrar _ethRegistryV1) {
        ethRegistryV1 = _ethRegistryV1;
    }

    struct MigrationData {
        string label;
        address owner;
        uint64 expires;
    }

    /**
     * Implements ERC165.supportsInterface
     */
    function supportsInterface(bytes4 interfaceId) public virtual view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(MigrationController).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(IERC721Receiver).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * Implements ERC1155Receiver.onERC1155Received
     */
    function onERC1155Received(address /*operator*/, address /*from*/, uint256 tokenId, uint256 /*amount*/, bytes calldata data) external virtual returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    /**
     * Implements ERC1155Receiver.onERC1155BatchReceived
     */
    function onERC1155BatchReceived(address /*operator*/, address /*from*/, uint256[] memory tokenIds, uint256[] memory /*amounts*/, bytes calldata data) external virtual returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    /**
     * @dev Implements ERC721Receiver.onERC721Received
     *
     * If this is called then it means an unwrapped .eth name is being migrated to v2.
     */
    function onERC721Received(address /*operator*/, address from, uint256 tokenId, bytes calldata data) external virtual returns (bytes4) {
        if (msg.sender != address(ethRegistryV1)) {
            revert CallerNotEthRegistryV1(msg.sender);
        }

        if (ethRegistryV1.ownerOf(tokenId) != address(this)) {
            revert NotOwner(from);
        }

        (string memory label) = abi.decode(data, (string));

        _migrateUnwrappedEthName(label, tokenId, from);

        return this.onERC721Received.selector;
    }

    // Internal functions

    /**
     * @dev Called when an unwrapped .eth name is being migrated to v2.
     *
     * @param label The label of the .eth name.
     * @param tokenId The token ID of the .eth name.
     * @param from The address of the owner of the .eth name.
     */
    function _migrateUnwrappedEthName(string memory label, uint256 tokenId, address from) internal virtual; 
}
