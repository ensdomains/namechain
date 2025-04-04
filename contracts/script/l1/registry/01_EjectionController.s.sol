// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "../../shared/Script.sol";

import {DeployUtils} from "../../shared/utils.sol";
import {MockEjectionController} from "../../../src/mock/MockEjectionController.sol";

// TODO: Replace with actual ejection controller
contract EjectionControllerDeploy is Script {
    MockEjectionController public ejectionController;

    function setUp() public {
        requireL1();
    }

    function run() public save("MockEjectionController") broadcast {
        ejectionController = new MockEjectionController();
    }
}
