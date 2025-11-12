// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering, one-contract-per-file

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {IRegistryCrier} from "~src/common/registry/interfaces/IRegistryCrier.sol";
import {RegistryCrier} from "~src/common/registry/RegistryCrier.sol";

contract RegistryCrierTest is Test {
    RegistryCrier crier;

    function setUp() public {
        crier = new RegistryCrier();
    }

    function test_NewRegistry_EmitsWhenCalled() public {
        address registryAddress = address(0x1234);

        vm.recordLogs();
        crier.newRegistry(registryAddress);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "Expected event when newRegistry is called");
        assertEq(logs[0].topics[0], keccak256("NewRegistry(address)"), "Wrong event signature");
        assertEq(
            address(uint160(uint256(logs[0].topics[1]))),
            registryAddress,
            "Wrong registry address"
        );
    }

    function test_NewRegistry_CanBeCalledByAnyone() public {
        address caller1 = makeAddr("caller1");
        address caller2 = makeAddr("caller2");
        address registry1 = address(0x1111);
        address registry2 = address(0x2222);

        // Caller 1 can call
        vm.prank(caller1);
        crier.newRegistry(registry1);

        // Caller 2 can also call
        vm.prank(caller2);
        crier.newRegistry(registry2);

        // Verify both calls succeeded (no revert means success)
        assertTrue(true);
    }
}
