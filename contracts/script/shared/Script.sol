// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script as ForgeScript} from "forge-std/Script.sol";
import {VmSafe, Vm} from "forge-std/Vm.sol";
import {StdStorage} from "forge-std/StdStorage.sol";
import {console} from "forge-std/console.sol";

contract DeploymentManager {
    VmSafe private constant vm =
        VmSafe(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D));

    mapping(string => address) _cachedDeployments;

    function saveDeployment(string memory name, address deployment) external {
        _cachedDeployments[name] = deployment;
    }

    function getDeployment(string memory name) external view returns (address) {
        if (_cachedDeployments[name] != address(0)) {
            return _cachedDeployments[name];
        }

        address deployment = vm.getDeployment(name);
        return deployment;
    }
}

contract Script is ForgeScript {
    DeploymentManager internal constant deployments =
        DeploymentManager(
            address(uint160(uint256(keccak256("DeploymentManager"))))
        );

    modifier broadcast() {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        _;
        vm.stopBroadcast();
    }

    modifier save(string memory name) {
        _;
        address deployment;
        assembly {
            deployment := sload(0x0c)
            deployment := shr(24, deployment)
        }
        deployments.saveDeployment(name, deployment);
        console.log("Deployment saved:", name, deployment);
    }

    constructor() {
        if (address(deployments).code.length == 0) {
            DeploymentManager _deployments = new DeploymentManager();
            vm.etch(address(deployments), address(_deployments).code);
            vm.allowCheatcodes(address(deployments));
        }
    }

    error NotL1Chain();
    error NotL2Chain();

    function isL1() internal view returns (bool) {
        return vm.envInt("CHAIN_TYPE") == 1;
    }

    function isL2() internal view returns (bool) {
        return vm.envInt("CHAIN_TYPE") == 2;
    }

    function requireL1() internal view {
        if (!isL1()) revert NotL1Chain();
    }

    function requireL2() internal view {
        if (!isL2()) revert NotL2Chain();
    }
}
