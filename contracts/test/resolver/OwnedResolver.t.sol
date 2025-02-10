// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {OwnedResolver} from "../../src/resolver/OwnedResolver.sol";
import {VerifiableFactory} from "verifiable-factory/VerifiableFactory.sol";
import {UUPSProxy} from "verifiable-factory/UUPSProxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAddrResolver} from "@ens/contracts/resolvers/profiles/IAddrResolver.sol";
import {IABIResolver} from "@ens/contracts/resolvers/profiles/IABIResolver.sol";
import {IContentHashResolver} from "@ens/contracts/resolvers/profiles/IContentHashResolver.sol";
import {IDNSRecordResolver} from "@ens/contracts/resolvers/profiles/IDNSRecordResolver.sol";
import {IInterfaceResolver} from "@ens/contracts/resolvers/profiles/IInterfaceResolver.sol";
import {INameResolver} from "@ens/contracts/resolvers/profiles/INameResolver.sol";
import {IPubkeyResolver} from "@ens/contracts/resolvers/profiles/IPubkeyResolver.sol";
import {ITextResolver} from "@ens/contracts/resolvers/profiles/ITextResolver.sol";
import {console} from "forge-std/console.sol";

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
        UUPSProxy proxy = UUPSProxy(payable(address(resolver)));
        assertEq(proxy.getVerifiableProxySalt(), SALT);
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

    function test_supports_interface() public {
        // Test for implemented interfaces        
        assertTrue(resolver.supportsInterface(type(IABIResolver).interfaceId), "Should support ABIResolver");
        assertTrue(resolver.supportsInterface(type(IContentHashResolver).interfaceId), "Should support ContentHashResolver");
        assertTrue(resolver.supportsInterface(type(IDNSRecordResolver).interfaceId), "Should support DNSResolver");
        assertTrue(resolver.supportsInterface(type(IInterfaceResolver).interfaceId), "Should support InterfaceResolver");
        assertTrue(resolver.supportsInterface(type(INameResolver).interfaceId), "Should support NameResolver");
        assertTrue(resolver.supportsInterface(type(IPubkeyResolver).interfaceId), "Should support PubkeyResolver");
        assertTrue(resolver.supportsInterface(type(ITextResolver).interfaceId), "Should support TextResolver");
        
        // Test for ERC165 interface
        assertTrue(resolver.supportsInterface(0x01ffc9a7), "Should support ERC165");
        
        // Test for unsupported interface
        assertFalse(resolver.supportsInterface(0xffffffff), "Should not support random interface");
    }
} 