// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "../shared/Script.sol";

import {RegistryDatastoreDeploy} from "../shared/RegistryDatastore.s.sol";
import {RootRegistryDeploy} from "./registry/00_RootRegistry.s.sol";
import {EjectionControllerDeploy} from "./registry/01_EjectionController.s.sol";
import {L1ETHRegistryDeploy} from "./registry/02_L1ETHRegistry.s.sol";

contract L1Deploy is Script {
    RegistryDatastoreDeploy registryDatastoreDeploy;
    RootRegistryDeploy rootRegistryDeploy;
    EjectionControllerDeploy ejectionControllerDeploy;
    L1ETHRegistryDeploy l1EthRegistryDeploy;

    function setUp() public {
        requireL1();
        registryDatastoreDeploy = new RegistryDatastoreDeploy();
        rootRegistryDeploy = new RootRegistryDeploy();
        ejectionControllerDeploy = new EjectionControllerDeploy();
        l1EthRegistryDeploy = new L1ETHRegistryDeploy();
    }

    function run() public {
        registryDatastoreDeploy.setUp();
        registryDatastoreDeploy.run();

        rootRegistryDeploy.setUp();
        rootRegistryDeploy.run();

        ejectionControllerDeploy.setUp();
        ejectionControllerDeploy.run();

        l1EthRegistryDeploy.setUp();
        l1EthRegistryDeploy.run();
    }
}
