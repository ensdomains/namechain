// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "../../shared/Script.sol";

import {DeployUtils} from "../../shared/utils.sol";
import {RootRegistry} from "../../../src/registry/RootRegistry.sol";
import {RegistryDatastore} from "../../../src/registry/RegistryDatastore.sol";

contract RootRegistryDeploy is Script {
    RootRegistry public registry;

    RegistryDatastore public datastore;

    function setUp() public {
        requireL1();
        datastore = RegistryDatastore(
            deployments.getDeployment("RegistryDatastore")
        );
    }

    function run() public save("RootRegistry") broadcast {
        registry = new RootRegistry(datastore);
        registry.grantRole(registry.TLD_ISSUER_ROLE(), address(this));
    }
}
