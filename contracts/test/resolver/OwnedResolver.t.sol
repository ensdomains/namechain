// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {OwnedResolver} from "../../src/resolver/OwnedResolver.sol";
import {VerifiableFactory} from "verifiable-factory/VerifiableFactory.sol";
import {TransparentVerifiableProxy} from "verifiable-factory/TransparentVerifiableProxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract OwnedResolverTest is Test {
    VerifiableFactory factory;
    uint256 constant SALT = 12345;
    address public owner;
    OwnedResolver resolver;
    bytes32 constant TEST_NODE = bytes32(uint256(1));
    uint256 constant ETH_COIN_TYPE = 60;

    function setUp() public {
        owner = makeAddr("owner");
        factory = new VerifiableFactory();
        
        address implementation = address(new OwnedResolver());
        bytes memory initData = abi.encodeWithSelector(OwnedResolver.initialize.selector, owner);
        vm.startPrank(owner);
        address deployed = factory.deployProxy(implementation, SALT, initData);
        vm.stopPrank();
        
        resolver = OwnedResolver(deployed);
    }

    function test_deploy() public {
        TransparentVerifiableProxy proxy = TransparentVerifiableProxy(payable(address(resolver)));
        assertEq(proxy.getVerifiableProxySalt(), SALT);
        assertEq(proxy.getVerifiableProxyOwner(), owner);
        assertEq(resolver.owner(), owner);
    }

    function test_set_and_get_addr() public {
        bytes memory ethAddress = abi.encodePacked(address(0x123));
        
        vm.startPrank(owner);
        resolver.setAddr(TEST_NODE, ETH_COIN_TYPE, ethAddress);
        vm.stopPrank();

        bytes memory retrievedAddr = resolver.addr(TEST_NODE, ETH_COIN_TYPE);
        assertEq(retrievedAddr, ethAddress);
    }

    function test_cannot_set_addr_if_not_owner() public {
        bytes memory ethAddress = abi.encodePacked(address(0x123));
        
        vm.startPrank(makeAddr("notOwner"));
        vm.expectRevert();
        resolver.setAddr(TEST_NODE, ETH_COIN_TYPE, ethAddress);
        vm.stopPrank();
    }

    function test_versionable_addresses() public {
        bytes memory addr1 = abi.encodePacked(address(0x123));
        bytes memory addr2 = abi.encodePacked(address(0x456));
        
        vm.startPrank(owner);
        // Set initial address
        resolver.setAddr(TEST_NODE, ETH_COIN_TYPE, addr1);
        assertEq(resolver.addr(TEST_NODE, ETH_COIN_TYPE), addr1);
        
        // Get current version and verify new address is stored under new version
        uint64 version = resolver.recordVersions(TEST_NODE);
        resolver.setAddr(TEST_NODE, ETH_COIN_TYPE, addr2);
        assertEq(resolver.addr(TEST_NODE, ETH_COIN_TYPE), addr2);
        vm.stopPrank();
    }
} 