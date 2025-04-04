// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "../../shared/Script.sol";
import {console} from "forge-std/console.sol";

import {DeployUtils} from "../../shared/utils.sol";
import {ETHRegistry} from "../../../src/registry/ETHRegistry.sol";
import {ETHRegistrar} from "../../../src/registry/ETHRegistrar.sol";
import {RegistryDatastore} from "../../../src/registry/RegistryDatastore.sol";
import {BaseUriRegistryMetadata} from "../../../src/registry/BaseUriRegistryMetadata.sol";
import {MockPriceOracle} from "../../../src/mock/MockPriceOracle.sol";

contract ETHRegistrarDeploy is Script {
    ETHRegistrar public registrar;

    ETHRegistry public registry;
    MockPriceOracle public priceOracle;

    uint256 constant MIN_COMMITMENT_AGE = 60; // 1 minute
    uint256 constant MAX_COMMITMENT_AGE = 86400; // 1 day

    function setUp() public {
        requireL2();
        registry = ETHRegistry(deployments.getDeployment("ETHRegistry"));
        // TODO: Replace with actual price oracle
        priceOracle = MockPriceOracle(
            deployments.getDeployment("MockPriceOracle")
        );
    }

    function run() public save("ETHRegistrar") broadcast {
        registrar = new ETHRegistrar(
            address(registry),
            priceOracle,
            MIN_COMMITMENT_AGE,
            MAX_COMMITMENT_AGE
        );
        registry.grantRole(registry.REGISTRAR_ROLE(), address(registrar));
    }
}
