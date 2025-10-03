// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering, one-contract-per-file

import {Test} from "forge-std/Test.sol";

import {HCAContextUpgradable} from "~src/common/hca/HCAContextUpgradable.sol";
import {HCAEquivalence} from "~src/common/hca/HCAEquivalence.sol";
import {IHCAFactoryBasic} from "~src/common/hca/interfaces/IHCAFactoryBasic.sol";
import {MockHCAFactoryBasic} from "~test/mocks/MockHCAFactoryBasic.sol";

contract HCAContextUpgradableHarness is HCAContextUpgradable {
    constructor(IHCAFactoryBasic factory) HCAEquivalence(factory) {}

    function exposedMsgSender() external view returns (address) {
        return _msgSender();
    }
}

contract HCAContextUpgradableTest is Test {
    MockHCAFactoryBasic factory;
    HCAContextUpgradableHarness harness;

    address user = address(0x1111);
    address hca = address(0xAAAA);
    address owner = address(0xBEEF);

    function setUp() public {
        factory = new MockHCAFactoryBasic();
        harness = new HCAContextUpgradableHarness(factory);
    }

    function test_constructor_sets_factory() public view {
        // HCA_FACTORY is public immutable on the base, accessible via harness
        assertEq(address(harness.HCA_FACTORY()), address(factory));
    }

    function test_msgSender_calls_HCAEquivalence() public {
        vm.prank(user);
        vm.expectCall(
            address(factory),
            abi.encodeWithSelector(factory.getAccountOwner.selector, user)
        );
        address sender = harness.exposedMsgSender();
        assertEq(sender, user);
    }
}
