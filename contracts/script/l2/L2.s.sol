// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "../shared/Script.sol";

import {RegistryDatastoreDeploy} from "../shared/RegistryDatastore.s.sol";
import {BaseUriRegistryMetadataDeploy} from "./registry/00_BaseUriRegistryMetadata.s.sol";
import {PriceOracleDeploy} from "./registry/00_PriceOracle.s.sol";
import {ETHRegistryDeploy} from "./registry/01_ETHRegistry.s.sol";
import {ETHRegistrarDeploy} from "./registry/02_ETHRegistrar.s.sol";

contract L1Deploy is Script {
    RegistryDatastoreDeploy registryDatastoreDeploy;
    BaseUriRegistryMetadataDeploy baseUriRegistryMetadataDeploy;
    PriceOracleDeploy priceOracleDeploy;
    ETHRegistryDeploy ethRegistryDeploy;
    ETHRegistrarDeploy ethRegistrarDeploy;

    function setUp() public {
        requireL2();
        registryDatastoreDeploy = new RegistryDatastoreDeploy();
        baseUriRegistryMetadataDeploy = new BaseUriRegistryMetadataDeploy();
        priceOracleDeploy = new PriceOracleDeploy();
        ethRegistryDeploy = new ETHRegistryDeploy();
        ethRegistrarDeploy = new ETHRegistrarDeploy();
    }

    function run() public {
        registryDatastoreDeploy.setUp();
        registryDatastoreDeploy.run();

        baseUriRegistryMetadataDeploy.setUp();
        baseUriRegistryMetadataDeploy.run();

        priceOracleDeploy.setUp();
        priceOracleDeploy.run();

        ethRegistryDeploy.setUp();
        ethRegistryDeploy.run();

        ethRegistrarDeploy.setUp();
        ethRegistrarDeploy.run();
    }
}
