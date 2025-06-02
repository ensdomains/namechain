// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IBridge} from "./IBridge.sol";
import {IRegistry} from "../common/IRegistry.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {L1EjectionController} from "../L1/L1EjectionController.sol";
import {TransferData} from "../common/EjectionController.sol";

/**
 * @title MockL1EjectionController
 * @dev Controller for handling L1 ENS operations with PermissionedRegistry
 */
contract MockL1EjectionController is L1EjectionController {
    IBridge public bridge;
    
    // Events for tracking actions
    event NameEjected(uint256 labelHash, address owner, address subregistry, uint64 expires);
    event NameMigrated(uint256 tokenId, address l2Owner, address l2Subregistry);
    event RenewalSynced(uint256 tokenId, uint64 newExpiry);
    
    constructor(IPermissionedRegistry _registry, IBridge _bridge) L1EjectionController(_registry) {
        bridge = _bridge;
    }

    function _onEject(uint256[] memory tokenIds, TransferData[] memory transferDataArray) internal override virtual {
        super._onEject(tokenIds, transferDataArray);
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            bridge.sendMessageToL2(tokenIds[i], transferDataArray[i]);
            emit NameMigrated(tokenIds[i], transferDataArray[i].owner, transferDataArray[i].subregistry);
        }
    }
    
    /**
     * @dev Handles completion of ejection from L2
     */
    function completeEjectionFromL2(
        TransferData memory transferData
    ) external returns (uint256 tokenId) {
        tokenId = _completeEjectionFromL2(transferData);
        emit NameEjected(tokenId, transferData.owner, transferData.subregistry, transferData.expires);
    }

    /**
     * @dev Handles synchronization of renewals from L2
     */
    function syncRenewalFromL2(uint256 tokenId, uint64 newExpiry) external {
        super._syncRenewal(tokenId, newExpiry);
        emit RenewalSynced(tokenId, newExpiry);
    }
}
