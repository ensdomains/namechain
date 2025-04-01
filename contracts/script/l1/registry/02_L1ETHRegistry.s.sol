// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "../../shared/Script.sol";

import {DeployUtils} from "../../shared/utils.sol";
import {RegistryDatastore} from "../../../src/registry/RegistryDatastore.sol";
import {L1ETHRegistry} from "../../../src/registry/L1ETHRegistry.sol";
import {MockEjectionController} from "../../../src/mock/MockEjectionController.sol";

contract L1ETHRegistryDeploy is Script {
    L1ETHRegistry public registry;

    RegistryDatastore public datastore;
    MockEjectionController public ejectionController;

    function setUp() public {
        requireL1();
        datastore = RegistryDatastore(
            deployments.getDeployment("RegistryDatastore")
        );
        // TODO: Replace with actual ejection controller
        ejectionController = MockEjectionController(
            deployments.getDeployment("MockEjectionController")
        );
    }

    function run() public save("L1ETHRegistry") broadcast {
        registry = new L1ETHRegistry(datastore, address(ejectionController));
    }
}
