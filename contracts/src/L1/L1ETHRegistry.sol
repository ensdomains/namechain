// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {ERC1155Singleton} from "../common/ERC1155Singleton.sol";
import {IERC1155Singleton} from "../common/IERC1155Singleton.sol";
import {IRegistry} from "../common/IRegistry.sol";
import {IRegistryDatastore} from "../common/IRegistryDatastore.sol";
import {BaseRegistry} from "../common/BaseRegistry.sol";
import {IRegistryMetadata} from "../common/IRegistryMetadata.sol";
import {IStandardRegistry} from "../common/IStandardRegistry.sol";
import {RegistryRolesMixin} from "../common/RegistryRolesMixin.sol";
import {PermissionedRegistry} from "../common/PermissionedRegistry.sol";
import {ETHRegistry} from "../common/ETHRegistry.sol";
import {IL1EjectionController} from "./IL1EjectionController.sol";

/**
 * @title L1ETHRegistry
 * @dev L1 contract for .eth that holds ejected .eth names only.
 * Unlike the L2 ETHRegistry, this registry does not handle new registrations directly,
 * but receives names that have been ejected from L2.
 */
contract L1ETHRegistry is ETHRegistry {
    error NameNotExpired(uint256 tokenId, uint64 expires);

    event NameMigratedToL2(uint256 indexed tokenId, address l2Owner, address l2Subregistry, address l2Resolver);
    event NameEjectedFromL2(uint256 indexed tokenId, address l1Owner, address l1Subregistry, address l1Resolver, uint64 expires);

    constructor(IRegistryDatastore _datastore, IRegistryMetadata _registryMetadata, IL1EjectionController _ejectionController) ETHRegistry(_datastore, _registryMetadata, _ejectionController) {
    }

    /**
     * @dev Receive an ejected name from Namechain.
     * @param tokenId The token ID of the name
     * @param owner The owner of the name
     * @param registry The registry to use for the name
     * @param resolver The resolver to use for the name
     * @param expires Expiration timestamp
     * @return tokenId The token ID of the ejected name
     */
    function ejectFromNamechain(uint256 tokenId, address owner, IRegistry registry, address resolver, uint64 expires)
        public
        onlyEjectionController
        returns (uint256)
    {
        // Check if the name is active (not expired)
        (, uint64 oldExpires, uint32 tokenIdVersion) = datastore.getSubregistry(tokenId);
        if (oldExpires >= block.timestamp) {
            revert NameNotExpired(tokenId, oldExpires);
        }

        // Get the actual owner without checking expiration
        address actualOwner = ERC1155Singleton.ownerOf(tokenId);
        if (actualOwner != address(0)) {
            // Burn the token from the actual owner
            _burn(actualOwner, tokenId, 1);
        }

        _mint(owner, tokenId, 1, "");

        datastore.setSubregistry(tokenId, address(registry), expires, tokenIdVersion);
        datastore.setResolver(tokenId, resolver, expires, 0);

        emit NameEjectedFromL2(tokenId, owner, address(registry), resolver, expires);
        return tokenId;
    }

    /**
     * @dev Update expiration date for a name. This can only be called by the ejection controller
     * when it receives a notification from L2 about a renewal.
     *
     * @param tokenId The token ID of the name to update
     * @param expires New expiration timestamp
     */
    function updateExpiration(uint256 tokenId, uint64 expires) 
        public 
        onlyEjectionController
    {
        (address subregistry, uint64 oldExpiration, uint32 tokenIdVersion) = datastore.getSubregistry(tokenId);
        
        if (oldExpiration < block.timestamp) {
            revert NameExpired(tokenId);
        }
        
        if (expires < oldExpiration) {
            revert CannotReduceExpiration(oldExpiration, expires);
        }
        
        datastore.setSubregistry(tokenId, subregistry, expires, tokenIdVersion);
        
        emit NameRenewed(tokenId, expires, msg.sender);
    }

    /**
     * @dev Migrate a name back to Namechain, preserving ownership on Namechain.
     * According to section 4.5.6 of the design doc, this process requires
     * the ejection controller to facilitate cross-chain communication.
     * @param tokenId The token ID of the name to migrate
     * @param l2Owner The address to send the name to on L2
     * @param l2Subregistry The subregistry to use on L2 (optional)
     * @param l2Resolver The resolver to use on L2 (optional)
     * @param data Extra data
     */
    function migrateToNamechain(uint256 tokenId, address l2Owner, address l2Subregistry, address l2Resolver, bytes memory data) external onlyTokenOwner(tokenId) {
        address owner = ownerOf(tokenId);
        _burn(owner, tokenId, 1);
        datastore.setSubregistry(tokenId, address(0), 0, 0);

        // Notify the ejection controller to handle cross-chain messaging
        // expiry is set to 0 since L2 will handle the expiry
        IL1EjectionController(address(ejectionController)).migrateToNamechain(tokenId, l2Owner, l2Subregistry, l2Resolver, data);

        emit NameMigratedToL2(tokenId, l2Owner, l2Subregistry, l2Resolver);
    }

}