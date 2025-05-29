// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IBridge} from "./IBridge.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {IRegistry} from "../common/IRegistry.sol";
import {L2EjectionController} from "../L2/L2EjectionController.sol";
import {TransferData} from "../common/EjectionController.sol";

/**
 * @title MockL2EjectionController
 * @dev Controller for handling L2 ENS operations with PermissionedRegistry
 */
contract MockL2EjectionController is L2EjectionController {
    IBridge public bridge;
    
    // Events for tracking actions
    event NameMigrated(uint256 labelHash, address owner, address subregistry);
    event NameEjected(uint256 tokenId, address l1Owner, address l1Subregistry, uint64 expires);
    
    constructor(IPermissionedRegistry _registry, IBridge _bridge) L2EjectionController(_registry) {
        bridge = _bridge;
    }

    function _onEject(uint256[] memory tokenIds, TransferData[] memory transferDataArray) internal override virtual {
        super._onEject(tokenIds, transferDataArray);
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            bridge.sendMessageToL1(tokenIds[i], transferDataArray[i]);
            emit NameEjected(tokenIds[i], transferDataArray[i].owner, transferDataArray[i].subregistry, transferDataArray[i].expires);
        }
    }

    function completeMigrationFromL1(
        uint256 tokenId,
        TransferData memory transferData
    ) external {
        transferData.resolver = address(0);
        transferData.roleBitmap = 0xF;
        transferData.expires = uint64(block.timestamp + 365 days);

        _completeMigrationFromL1(tokenId, transferData);

        emit NameMigrated(tokenId, transferData.owner, transferData.subregistry);
    }    

    function onRenew(uint256 tokenId, uint64 expires, address renewedBy) external override {
    }

    function onRelinquish(uint256 tokenId, address relinquishedBy) external override {
    }
}
