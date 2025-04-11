// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "../../shared/Script.sol";
import {console} from "forge-std/console.sol";

import {DeployUtils} from "../../shared/utils.sol";
import {ETHRegistry} from "../../../src/registry/ETHRegistry.sol";
import {RegistryDatastore} from "../../../src/registry/RegistryDatastore.sol";
import {BaseUriRegistryMetadata} from "../../../src/registry/BaseUriRegistryMetadata.sol";

contract ETHRegistryDeploy is Script {
    ETHRegistry public registry;

    RegistryDatastore public datastore;
    BaseUriRegistryMetadata public metadata;

    function setUp() public {
        requireL2();
        datastore = RegistryDatastore(
            deployments.getDeployment("RegistryDatastore")
        );
        metadata = BaseUriRegistryMetadata(
            deployments.getDeployment("BaseUriRegistryMetadata")
        );
    }

    function run() public save("ETHRegistry") broadcast {
        registry = new ETHRegistry(datastore, metadata);
    }
}
