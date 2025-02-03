// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {OwnedResolver} from "../../src/resolver/OwnedResolver.sol";
import {VerifiableFactory} from "../../lib/verifiable-factory/src/VerifiableFactory.sol";
import {TransparentVerifiableProxy} from "../../lib/verifiable-factory/src/TransparentVerifiableProxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract OwnedResolverTest is Test {
    VerifiableFactory factory;
    uint256 constant SALT = 12345;
    address public owner;

    function setUp() public {
        owner = makeAddr("owner");
        factory = new VerifiableFactory();
    }

    function testDeploy() public {
        address implementation = address(new OwnedResolver());
        bytes memory data = "";
        vm.startPrank(owner);
        address deployed = factory.deployProxy(implementation, SALT, data);
        vm.stopPrank();
        assertTrue(deployed != address(0));
        assertTrue(deployed.code.length > 0);
        
        TransparentVerifiableProxy proxy = TransparentVerifiableProxy(payable(deployed));
        // Check salt matches
        assertEq(proxy.salt(), SALT);

        // Check owner is msg.sender
        assertEq(proxy.owner(), owner);
    }
} 