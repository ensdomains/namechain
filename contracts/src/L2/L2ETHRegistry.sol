// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {IL2EjectionController} from "./IL2EjectionController.sol";
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

/**
 * @title L2ETHRegistry
 * @dev L2 contract for .eth that holds .eth names.
 */
contract L2ETHRegistry is ETHRegistry {
    error NameNotExpired(uint256 tokenId, uint64 expires);

    event NameEjectedToL1(uint256 indexed tokenId, address l1Owner, address l1Subregistry, address l1Resolver);

    constructor(IRegistryDatastore _datastore, IRegistryMetadata _registryMetadata, address _ejectionController) ETHRegistry(_datastore, _registryMetadata, _ejectionController) {
    }

    /**
     * @dev Eject a name to L1.
     * @param tokenId The token ID of the name
     * @param l1Owner The new owner of the name on L1
     * @param l1Subregistry The new subregistry to use for the name on L1
     * @param l1Resolver The new resolver to use for the name on L1
     */
    function eject(uint256 tokenId, address l1Owner, address l1Subregistry, address l1Resolver)
        public
        onlyTokenOwner(tokenId)
    {
        setTokenObserver(tokenId, IL2EjectionController(address(ejectionController)));
        _safeTransferFrom(msg.sender, address(ejectionController), tokenId, 1, abi.encode(l1Owner, l1Subregistry, l1Resolver));
        emit NameEjectedToL1(tokenId, l1Owner, l1Subregistry, l1Resolver);
    }
}
