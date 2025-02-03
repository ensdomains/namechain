// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {OwnedResolver} from "../../src/resolver/OwnedResolver.sol";

contract OwnedResolverTest is Test {
    function testDeploy() public {
        OwnedResolver resolver = new OwnedResolver();
        assertTrue(address(resolver) != address(0));
    }
} 