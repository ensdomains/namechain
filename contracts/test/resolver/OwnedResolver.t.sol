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

    function testDeploy() public {
        TransparentVerifiableProxy proxy = TransparentVerifiableProxy(payable(address(resolver)));
        assertEq(proxy.getVerifiableProxySalt(), SALT);
        assertEq(proxy.getVerifiableProxyOwner(), owner);
        assertEq(resolver.owner(), owner);
    }

    function testSetAndGetAddr() public {
        bytes memory ethAddress = abi.encodePacked(address(0x123));
        
        vm.startPrank(owner);
        resolver.setAddr(TEST_NODE, ETH_COIN_TYPE, ethAddress);
        vm.stopPrank();

        bytes memory retrievedAddr = resolver.addr(TEST_NODE, ETH_COIN_TYPE);
        assertEq(retrievedAddr, ethAddress);
    }

    function testCannotSetAddrIfNotOwner() public {
        bytes memory ethAddress = abi.encodePacked(address(0x123));
        
        vm.startPrank(makeAddr("notOwner"));
        vm.expectRevert();
        resolver.setAddr(TEST_NODE, ETH_COIN_TYPE, ethAddress);
        vm.stopPrank();
    }

    function testVersionableAddresses() public {
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