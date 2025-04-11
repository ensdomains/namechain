// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "../../shared/Script.sol";

import {DeployUtils} from "../../shared/utils.sol";
import {MockPriceOracle} from "../../../src/mock/MockPriceOracle.sol";

// TODO: Replace with actual price oracle
contract PriceOracleDeploy is Script {
    MockPriceOracle public priceOracle;

    uint256 constant BASE_PRICE = 0.01 ether;
    uint256 constant PREMIUM_PRICE = 0.005 ether;

    function setUp() public view {
        requireL2();
    }

    function run() public save("MockPriceOracle") broadcast {
        priceOracle = new MockPriceOracle(BASE_PRICE, PREMIUM_PRICE);
    }
}
