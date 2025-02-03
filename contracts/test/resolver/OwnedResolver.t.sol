// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {OwnedResolver} from "../../src/resolver/OwnedResolver.sol";
import {VerifiableFactory} from "../../lib/verifiable-factory/src/VerifiableFactory.sol";

contract OwnedResolverTest is Test {
    VerifiableFactory factory;

    function setUp() public {
        factory = new VerifiableFactory();
    }

    function testDeploy() public {
        address implementation = address(new OwnedResolver());
        uint256 salt = 12345; // Example salt value
        bytes memory data = ""; // Initialization data if needed

        address deployed = factory.deployProxy(implementation, salt, data);
        assertTrue(deployed != address(0));
        assertTrue(deployed.code.length > 0);
    }
} 