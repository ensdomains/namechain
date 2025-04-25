// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {IEjectionController} from "../common/IEjectionController.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IRegistry} from "../common/IRegistry.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {RegistryRolesMixin} from "../common/RegistryRolesMixin.sol";
import {IL1ETHRegistry} from "./IL1ETHRegistry.sol";

/**
 * @title L1EjectionController
 * @dev L1 contract for ejection controller that facilitates migrations of names
 * between L1 and L2, as well as handling renewals.
 */
abstract contract L1EjectionController is IEjectionController, IERC1155Receiver, RegistryRolesMixin {
    error NotTokenOwner(uint256 tokenId);

    IL1ETHRegistry public immutable registry;

    struct TransferData {
        address l2Owner;
        address l2Subregistry;
        address l2Resolver;
        uint64 expires;
    }

    constructor(IL1ETHRegistry _registry) {
        registry = _registry;
    }

    /**
     * @dev Should be called when a name has been ejected from L2.  
     *
     * @param tokenId The token ID of the name being ejected
     * @param l1Owner The address that will own the name on L1
     * @param l1Subregistry The subregistry address to use on L1
     * @param l1Resolver The resolver address to use on L1
     */
    function _completeEjectionFromL2(
        uint256 tokenId,
        address l1Owner,
        address l1Subregistry,
        address l1Resolver,
        uint64 expires
    ) internal virtual {
        registry.ejectFromNamechain(tokenId, l1Owner, IRegistry(l1Subregistry), l1Resolver, expires);
    }

    /**
     * @dev Sync the renewal of a name with the L2 registry.
     *
     * @param tokenId The token ID of the name
     * @param newExpiry The new expiration timestamp
     */
    function _syncRenewal(uint256 tokenId, uint64 newExpiry) internal virtual {
        registry.renew(tokenId, newExpiry);
    }

    /**
     * Implements ERC165.supportsInterface
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IEjectionController).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId;
    }

    /**
     * Implements ERC1155Receiver.onERC1155Received
     */
    function onERC1155Received(address /*operator*/, address /*from*/, uint256 tokenId, uint256 /*amount*/, bytes calldata data) external override virtual returns (bytes4) {
        TransferData memory transferData = abi.decode(data, (TransferData));
        _onEjectToL2(tokenId, transferData);
        return this.onERC1155Received.selector;
    }

    /**
     * Implements ERC1155Receiver.onERC1155BatchReceived
     */
    function onERC1155BatchReceived(address /*operator*/, address /*from*/, uint256[] memory tokenIds, uint256[] memory /*amounts*/, bytes calldata data) external override virtual returns (bytes4) {
        TransferData[] memory transferDataArray = abi.decode(data, (TransferData[]));
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            TransferData memory transferData = transferDataArray[i];
            _onEjectToL2(tokenIds[i], transferData);
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
     * @dev Called when a name is ejected back to L2.
     *
     * @param tokenId The token ID of the name being ejected
     * @param transferData The transfer data containing l2Owner, l2Subregistry, l2Resolver, and expires
     */
    function _onEjectToL2(uint256 tokenId, TransferData memory transferData) internal virtual {
        if (registry.ownerOf(tokenId) != address(this)) {
            revert NotTokenOwner(tokenId);
        }

        registry.relinquish(tokenId);
    }
}
