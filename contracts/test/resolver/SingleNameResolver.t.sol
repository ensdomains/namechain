// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {SingleNameResolver} from "../../src/common/SingleNameResolver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract SingleNameResolverTest is Test {
    SingleNameResolver resolver;
    address owner = address(0x123);
    bytes32 testName = bytes32(uint256(0x3af03b0650c0604dcad87f782db476d0f1a73bf08331de780aec68a52b9e944c));

    function setUp() public {
        resolver = new SingleNameResolver();
        resolver.initialize(owner, testName);
    }

    function testInitialization() public {
        assertEq(resolver.owner(), owner);
        assertEq(resolver.associatedName(), testName);
    }

    function testSetAddr() public {
        vm.prank(owner);
        resolver.setAddr(address(0x456));
        assertEq(address(resolver.addr()), address(0x456));
    }

    function testSetAddrUnauthorized() public {
        vm.expectRevert("Ownable: caller is not the owner");
        resolver.setAddr(address(0x456));
    }

    function testSetCoinAddr() public {
        bytes memory ethAddr = hex"1234567890abcdef";
        vm.prank(owner);
        resolver.setAddr(60, ethAddr);
        assertEq(resolver.addr(60), ethAddr);
    }

    function testSetText() public {
        vm.prank(owner);
        resolver.setText("email", "test@example.com");
        assertEq(resolver.text("email"), "test@example.com");
    }

    function testSetContenthash() public {
        bytes memory hash = hex"1234567890";
        vm.prank(owner);
        resolver.setContenthash(hash);
        assertEq(resolver.contenthash(), hash);
    }

    function testSupportsInterface() public {
        assertTrue(resolver.supportsInterface(0x3b3b57de)); // addr(bytes32)
        assertTrue(resolver.supportsInterface(0xf1cb7e06)); // addr(uint256)
        assertTrue(resolver.supportsInterface(0x59d1d43c)); // text(bytes32,string)
        assertTrue(resolver.supportsInterface(0xbc1c58d1)); // contenthash(bytes32)
        assertTrue(resolver.supportsInterface(type(IERC165).interfaceId));
        assertFalse(resolver.supportsInterface(0x12345678)); // random interface
    }
}
