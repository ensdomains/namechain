// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering, one-contract-per-file

import {Test} from "forge-std/Test.sol";

import {HCAEquivalence} from "~src/common/hca/HCAEquivalence.sol";
import {IHCAFactoryBasic} from "~src/common/hca/interfaces/IHCAFactoryBasic.sol";
import {MockHCAFactoryBasic} from "~test/mocks/MockHCAFactoryBasic.sol";

contract HCAEquivalenceHarness is HCAEquivalence {
    constructor(IHCAFactoryBasic factory) HCAEquivalence(factory) {}

    function exposedMsgSender() external view returns (address) {
        return _msgSenderWithHcaEquivalence();
    }
}

contract HCAEquivalenceTest is Test {
    MockHCAFactoryBasic factory;
    HCAEquivalenceHarness harness;

    address user = address(0x1111);
    address hca = address(0xAAAA);
    address owner = address(0xBEEF);

    function setUp() public {
        factory = new MockHCAFactoryBasic();
        harness = new HCAEquivalenceHarness(IHCAFactoryBasic(address(factory)));
    }

    function test_constructor_sets_factory() public view {
        // HCA_FACTORY is public immutable on the base, accessible via harness
        assertEq(address(harness.HCA_FACTORY()), address(factory));
    }

    function test_msgSender_returns_original_when_not_hca() public {
        vm.prank(user);
        address sender = harness.exposedMsgSender();
        assertEq(sender, user, "_msgSender should return original sender when not HCA");
    }

    function test_msgSender_returns_owner_when_sender_is_hca() public {
        factory.setAccountOwner(hca, owner);

        vm.prank(hca);
        address sender = harness.exposedMsgSender();
        assertEq(sender, owner, "_msgSender should return account owner for HCA senders");
    }

    function test_msgSender_zero_owner_treated_as_eoa() public {
        // Ensure no owner configured for `user`
        vm.prank(user);
        address sender = harness.exposedMsgSender();
        assertEq(sender, user);
    }

    function test_msgSender_unrelated_mapping_does_not_affect_eoa() public {
        // Configure a different HCA mapping, but call from an unrelated EOA
        factory.setAccountOwner(hca, owner);

        vm.prank(user);
        address sender = harness.exposedMsgSender();
        assertEq(sender, user, "Unrelated mapping should not affect EOA sender");
    }

    function test_msgSender_owner_same_as_hca_returns_hca() public {
        // Edge: if factory maps HCA to itself, _msgSender returns that same address
        factory.setAccountOwner(hca, hca);

        vm.prank(hca);
        address sender = harness.exposedMsgSender();
        assertEq(sender, hca, "When owner == HCA, _msgSender should be the HCA address");
    }
}
