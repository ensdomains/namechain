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

    function _onEject(uint256[] memory tokenIds, TransferData[] memory transferDataArray) internal override virtual {
        super._onEject(tokenIds, transferDataArray);
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            bytes memory dnsEncodedName = _dnsEncodeLabel(transferDataArray[i].label);
            bridge.sendMessage(BridgeEncoder.encodeEjection(dnsEncodedName, transferDataArray[i]));
            emit NameEjectedToL1(dnsEncodedName, transferDataArray[i].owner, transferDataArray[i].subregistry, transferDataArray[i].expires);
        }
    }

    function completeMigrationFromL1(
        TransferData memory transferData
    ) external {
        transferData.resolver = address(0);
        transferData.roleBitmap = 0xF;
        transferData.expires = uint64(block.timestamp + 365 days);

        uint256 tokenId = NameUtils.labelToCanonicalId(transferData.label);

        _completeMigrationFromL1(tokenId, transferData);

        bytes memory dnsEncodedName = _dnsEncodeLabel(transferData.label);
        emit NameEjectedToL2(dnsEncodedName, transferData.owner, transferData.subregistry);
    }

    /**
     * @dev Handles completion of migration from L1 by decoding raw data
     */
    function completeMigrationFromL1(
        bytes memory data
    ) external {
        TransferData memory transferData = abi.decode(data, (TransferData));
        this.completeMigrationFromL1(transferData);
    }    

    function onRenew(uint256 tokenId, uint64 expires, address renewedBy) external override {
    }

    function onRelinquish(uint256 tokenId, address relinquishedBy) external override {
    }
}
