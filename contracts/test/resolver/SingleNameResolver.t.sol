// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {SingleNameResolver} from "../../src/common/SingleNameResolver.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";
import {UUPSProxy} from "@ensdomains/verifiable-factory/UUPSProxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/console.sol";

contract OwnedResolverTest is Test {
    VerifiableFactory factory;
    uint256 constant SALT = 12345;
    address public owner;
    SingleNameResolver resolver;
    uint256 constant ETH_COIN_TYPE = 60;

    function setUp() public {
        owner = makeAddr("owner");
        factory = new VerifiableFactory();
        
        address implementation = address(new SingleNameResolver());
        bytes memory initData = abi.encodeWithSelector(SingleNameResolver.initialize.selector, owner);
        vm.startPrank(owner);
        address deployed = factory.deployProxy(implementation, SALT, initData);
        vm.stopPrank();
        
        resolver = SingleNameResolver(deployed);
    }

    function test_deploy() public view {
        UUPSProxy proxy = UUPSProxy(payable(address(resolver)));
        bytes32 outerSalt = keccak256(abi.encode(owner, SALT));
        assertEq(proxy.getVerifiableProxySalt(), outerSalt);
        assertEq(resolver.owner(), owner);
    }

    function test_set_and_get_addr() public {
        bytes memory ethAddress = abi.encodePacked(address(0x123));
        
        vm.startPrank(owner);
        resolver.setAddr(ETH_COIN_TYPE, ethAddress);
        vm.stopPrank();

        bytes memory retrievedAddr = resolver.addr(ETH_COIN_TYPE);
        assertEq(retrievedAddr, ethAddress);
    }

    function test_cannot_set_addr_if_not_owner() public {
        bytes memory ethAddress = abi.encodePacked(address(0x123));
        
        vm.startPrank(makeAddr("notOwner"));
        vm.expectRevert();
        resolver.setAddr(ETH_COIN_TYPE, ethAddress);
        vm.stopPrank();
    }

    function test_versionable_addresses() public {
        bytes memory addr1 = abi.encodePacked(address(0x123));
        bytes memory addr2 = abi.encodePacked(address(0x456));
        
        vm.startPrank(owner);
        // Set initial address
        resolver.setAddr(ETH_COIN_TYPE, addr1);
        assertEq(resolver.addr(ETH_COIN_TYPE), addr1);
        
        // Update address
        resolver.setAddr(ETH_COIN_TYPE, addr2);
        assertEq(resolver.addr(ETH_COIN_TYPE), addr2);
        vm.stopPrank();
    }

    function test_supports_interface() view public {
        // Test for implemented interfaces        
        assertTrue(resolver.supportsInterface(0x3b3b57de), "Should support addr interface");
        assertTrue(resolver.supportsInterface(0xf1cb7e06), "Should support address interface");
        assertTrue(resolver.supportsInterface(0x59d1d43c), "Should support text interface");
        assertTrue(resolver.supportsInterface(0xbc1c58d1), "Should support contenthash interface");
        
        // Test for ERC165 interface
        assertTrue(resolver.supportsInterface(0x01ffc9a7), "Should support ERC165");
        
        // Test for unsupported interface
        assertFalse(resolver.supportsInterface(0xffffffff), "Should not support random interface");
    }
} 