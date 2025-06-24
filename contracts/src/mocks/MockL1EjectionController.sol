// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BridgeEncoder} from "../common/BridgeEncoder.sol";
import {IRegistry} from "../common/IRegistry.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {L1EjectionController} from "../L1/L1EjectionController.sol";
import {TransferData} from "../common/TransferData.sol";
import {MockL1Bridge} from "./MockL1Bridge.sol";
import {NameEjectedToL1, NameEjectedToL2} from "./MockEjectionControllerEvents.sol";
import {NameUtils} from "../common/NameUtils.sol";

/**
 * @title MockL1EjectionController
 * @dev Controller for handling L1 ENS operations with PermissionedRegistry
 */
contract MockL1EjectionController is L1EjectionController {
    MockL1Bridge public bridge;
    
    constructor(IPermissionedRegistry _registry, MockL1Bridge _bridge) L1EjectionController(_registry) {
        bridge = _bridge;
    }

    function completeEjectionFromL2(
        TransferData memory transferData
    ) public override returns (uint256 tokenId) {
        tokenId = super.completeEjectionFromL2(transferData);
        bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel(transferData.label);
        emit NameEjectedToL1(dnsEncodedName, transferData.owner, transferData.subregistry, transferData.expires);
    }

    function _onEject(uint256[] memory tokenIds, TransferData[] memory transferDataArray) internal override virtual {
        super._onEject(tokenIds, transferDataArray);
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel(transferDataArray[i].label);
            bridge.sendMessage(BridgeEncoder.encodeEjection(dnsEncodedName, transferDataArray[i]));
            emit NameEjectedToL2(dnsEncodedName, transferDataArray[i].owner, transferDataArray[i].subregistry);
        }
    }
}
