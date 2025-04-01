// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";

import {Script} from "../../shared/Script.sol";

import {DeployUtils} from "../../shared/utils.sol";
import {BaseUriRegistryMetadata} from "../../../src/registry/BaseUriRegistryMetadata.sol";

contract BaseUriRegistryMetadataDeploy is Script {
    BaseUriRegistryMetadata public metadata;

    function setUp() public view {
        requireL2();
    }

    function run() public save("BaseUriRegistryMetadata") broadcast {
        metadata = new BaseUriRegistryMetadata();
    }
}
