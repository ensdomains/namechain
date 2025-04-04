// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "./Script.sol";
import {RegistryDatastore} from "../../src/registry/RegistryDatastore.sol";

contract RegistryDatastoreDeploy is Script {
    address public datastore;

    function setUp() public {}

    function run() public save("RegistryDatastore") broadcast {
        datastore = address(new RegistryDatastore());
    }
}
