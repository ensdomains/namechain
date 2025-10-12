// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {INameWrapper} from "@ens/contracts/wrapper/INameWrapper.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";

import {TransferData} from "../../common/bridge/types/TransferData.sol";
import {L1BridgeController} from "../bridge/L1BridgeController.sol";

import {WrapperReceiver} from "./WrapperReceiver.sol";

contract LockedMigrationController2 is WrapperReceiver {
    ////////////////////////////////////////////////////////////////////////
    // Constants
    ////////////////////////////////////////////////////////////////////////

    L1BridgeController public immutable L1_BRIDGE_CONTROLLER;

    address public immutable MIGRATED_REGISTRY_IMPL;

    ////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////

    constructor(
        INameWrapper nameWrapper,
        L1BridgeController l1BridgeController,
        VerifiableFactory migratedRegistryFactory,
        address migratedRegistryImpl
    ) WrapperReceiver(nameWrapper, migratedRegistryFactory) {
        L1_BRIDGE_CONTROLLER = l1BridgeController;
        MIGRATED_REGISTRY_IMPL = migratedRegistryImpl;
    }

    ////////////////////////////////////////////////////////////////////////
    // Implementation
    ////////////////////////////////////////////////////////////////////////

    function _inject(TransferData memory td) internal override returns (uint256 tokenId) {
        return L1_BRIDGE_CONTROLLER.completeEjectionToL1(td);
    }

    function _registryImplementation() internal view override returns (address) {
        return MIGRATED_REGISTRY_IMPL;
    }

    function _parentNode() internal pure override returns (bytes32) {
        return NameCoder.ETH_NODE;
    }
}
