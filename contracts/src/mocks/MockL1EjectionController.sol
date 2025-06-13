// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BridgeEncoder, BridgeMessageType} from "../common/IBridge.sol";
import {IRegistry} from "../common/IRegistry.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {L1EjectionController} from "../L1/L1EjectionController.sol";
import {TransferData} from "../common/TransferData.sol";
import {MockL1Bridge} from "./MockL1Bridge.sol";
import {IL1Migrator} from "../L1/IL1Migrator.sol";
import {NameEjectedToL1, NameEjectedToL2} from "./MockEjectionControllerEvents.sol";

/**
 * @title MockL1EjectionController
 * @dev Controller for handling L1 ENS operations with PermissionedRegistry
 */
contract MockL1EjectionController is L1EjectionController, IL1Migrator {
    MockL1Bridge public bridge;
    
    event RenewalSynced(uint256 tokenId, uint64 newExpiry);
    
    constructor(IPermissionedRegistry _registry, MockL1Bridge _bridge) L1EjectionController(_registry) {
        bridge = _bridge;
    }

    function _onEject(uint256[] memory tokenIds, TransferData[] memory transferDataArray) internal override virtual {
        super._onEject(tokenIds, transferDataArray);
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            bytes memory dnsEncodedName = _dnsEncodeLabel(transferDataArray[i].label);
            bridge.sendMessage(BridgeEncoder.encode(BridgeMessageType.EJECTION, dnsEncodedName, abi.encode(transferDataArray[i])));
            emit NameEjectedToL2(dnsEncodedName, transferDataArray[i].owner, transferDataArray[i].subregistry);
        }
    }

    /**
     * @dev Migrates a name from v1 to v2 on L1
     */
    function migrateFromV1(TransferData memory transferData) external {
        completeEjectionFromL2(transferData);
    }
    
    /**
     * @dev Handles completion of ejection from L2
     */
    function completeEjectionFromL2(
        TransferData memory transferData
    ) public returns (uint256 tokenId) {
        tokenId = _completeEjectionFromL2(transferData);
        bytes memory dnsEncodedName = _dnsEncodeLabel(transferData.label);
        emit NameEjectedToL1(dnsEncodedName, transferData.owner, transferData.subregistry, transferData.expires);
    }

    /**
     * @dev Handles synchronization of renewals from L2
     */
    function syncRenewalFromL2(uint256 tokenId, uint64 newExpiry) external {
        super._syncRenewal(tokenId, newExpiry);
        emit RenewalSynced(tokenId, newExpiry);
    }
}
