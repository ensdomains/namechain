// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IBridge} from "../common/IBridge.sol";
import {BridgeEncoder} from "../common/BridgeEncoder.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {IRegistry} from "../common/IRegistry.sol";
import {L2EjectionController} from "../L2/L2EjectionController.sol";
import {TransferData} from "../common/TransferData.sol";
import {NameUtils} from "../common/NameUtils.sol";
import {MockL2Bridge} from "./MockL2Bridge.sol";
import {NameEjectedToL1, NameEjectedToL2} from "./MockEjectionControllerEvents.sol";

/**
 * @title MockL2EjectionController
 * @dev Controller for handling L2 ENS operations with PermissionedRegistry
 */
contract MockL2EjectionController is L2EjectionController {
    MockL2Bridge public bridge;
    
    constructor(IPermissionedRegistry _registry, MockL2Bridge _bridge) L2EjectionController(_registry) {
        bridge = _bridge;
    }

    function completeMigrationFromL1(
        uint256 tokenId,
        TransferData memory transferData
    ) public override {
        super.completeMigrationFromL1(tokenId, transferData);
        bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel(transferData.label);
        emit NameEjectedToL2(dnsEncodedName, transferData.owner, transferData.subregistry);
    }

    function _onEject(uint256[] memory tokenIds, TransferData[] memory transferDataArray) internal override virtual {
        super._onEject(tokenIds, transferDataArray);
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
                    bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel(transferDataArray[i].label);
        bridge.sendMessage(BridgeEncoder.encodeEjection(dnsEncodedName, transferDataArray[i]));
        emit NameEjectedToL1(dnsEncodedName, transferDataArray[i].owner, transferDataArray[i].subregistry, transferDataArray[i].expires);
        }
    }

    function onRenew(uint256 tokenId, uint64 expires, address renewedBy) external override {
    }

    function onRelinquish(uint256 tokenId, address relinquishedBy) external override {
    }
}
