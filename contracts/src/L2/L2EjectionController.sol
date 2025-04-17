// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IStandardRegistry} from "../common/IStandardRegistry.sol";
import {ITokenObserver} from "../common/ITokenObserver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IRegistry} from "../common/IRegistry.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title L2EjectionController
 * @dev L2 contract for ejection controller that facilitates migrations of names
 * between L1 and L2, as well as handling renewals.
 */
contract L2EjectionController is ITokenObserver, IERC1155Receiver {
    error NotTokenOwner(uint256 tokenId);
    event NameRenewed(uint256 indexed tokenId, uint64 expires, address renewedBy);

    event NameEjectedToL1(uint256 indexed tokenId, address l1Owner, address l1Subregistry, address l1Resolver, uint64 expiry);
    event NameMigratedToL2(uint256 indexed tokenId, address l2Owner, address l2Subregistry, address l2Resolver);

    IStandardRegistry public immutable registry;

    constructor(IStandardRegistry _registry) {
        registry = _registry;
    }

    /**
     * @dev Called by the cross-chain messaging system when a name is being migrated back to L2.
     *
     * @param tokenId The token ID of the name being migrated
     * @param l2Owner The address that will own the name on L2
     * @param l2Subregistry The subregistry address to use on L2
     * @param l2Resolver The resolver address to use on L2
     */
    function completeMigrationFromL1(
        uint256 tokenId,
        address l2Owner,
        address l2Subregistry,
        address l2Resolver
    ) external virtual {
        if (registry.ownerOf(tokenId) != address(this)) {
            revert NotTokenOwner(tokenId);
        }

        registry.setSubregistry(tokenId, IRegistry(l2Subregistry));
        registry.setResolver(tokenId, l2Resolver);
        registry.safeTransferFrom(address(this), l2Owner, tokenId, 1, "");

        emit NameMigratedToL2(tokenId, l2Owner, l2Subregistry, l2Resolver);
    }

    /**
     * Implements ERC165.supportsInterface
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(ITokenObserver).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId;
    }

    /**
     * Implements ERC1155Receiver.onERC1155Received
     */
    function onERC1155Received(address /*operator*/, address /*from*/, uint256 tokenId, uint256 /*amount*/, bytes calldata data) external returns (bytes4) {
        _onEjectToL1(tokenId, data);
        return this.onERC1155Received.selector;
    }

    /**
     * Implements ERC1155Receiver.onERC1155BatchReceived
     */
    function onERC1155BatchReceived(address /*operator*/, address /*from*/, uint256[] memory tokenIds, uint256[] memory /*amounts*/, bytes calldata data) external returns (bytes4) {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _onEjectToL1(tokenIds[i], data);
        }
        return this.onERC1155BatchReceived.selector;
    }

    /**
     * Implements ITokenObserver.onRenew
     */
    function onRenew(uint256 tokenId, uint64 expires, address renewedBy) external {
        if (registry.ownerOf(tokenId) == address(this)) {
            // this will get picked up by the bridge
            emit NameRenewed(tokenId, expires, renewedBy);
        }
    }

    /**
     * Implements ITokenObserver.onRelinquish
     */
    function onRelinquish(uint256 tokenId, address relinquishedBy) external {
        // nothing to do here since a user can't relinquish an ejected name
    }

    // Internal functions

    function _onEjectToL1(uint256 tokenId, bytes memory data) internal {
        (address l1Owner, address l1Subregistry, address l1Resolver) = abi.decode(data, (address, address, address));

        if (registry.ownerOf(tokenId) != address(this)) {
            revert NotTokenOwner(tokenId);
        }

        uint64 expiry = registry.getExpiry(tokenId);

        registry.setSubregistry(tokenId, IRegistry(address(0)));

        // bridge will listen for this event        
        emit NameEjectedToL1(tokenId, l1Owner, l1Subregistry, l1Resolver, expiry);
    }
}
