// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {DedicatedResolver} from "../../src/common/DedicatedResolver.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";
import {UUPSProxy} from "@ensdomains/verifiable-factory/UUPSProxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {INameResolver} from "@ens/contracts/resolvers/profiles/INameResolver.sol";
import {console} from "forge-std/console.sol";

contract DedicatedResolverTest is Test {
    VerifiableFactory factory;
    uint256 constant SALT = 12345;
    address public owner;
    DedicatedResolver resolver;
    uint256 constant ETH_COIN_TYPE = 60;
    bytes32 constant TEST_NODE = bytes32(uint256(1)); // Test node for getter functions

    function setUp() public {
        owner = makeAddr("owner");
        factory = new VerifiableFactory();
        
        address implementation = address(new DedicatedResolver());
        bytes memory initData = abi.encodeWithSelector(DedicatedResolver.initialize.selector, owner);
        vm.startPrank(owner);
        address deployed = factory.deployProxy(implementation, SALT, initData);
        vm.stopPrank();
        
        resolver = DedicatedResolver(deployed);
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

        bytes memory retrievedAddr = resolver.addr(TEST_NODE, ETH_COIN_TYPE);
        assertEq(retrievedAddr, ethAddress);
    }

    function test_cannot_set_addr_if_not_owner() public {
        bytes memory ethAddress = abi.encodePacked(address(0x123));
        
        vm.startPrank(makeAddr("notOwner"));
        vm.expectRevert();
        resolver.setAddr(ETH_COIN_TYPE, ethAddress);
        vm.stopPrank();
    }


    function test_supports_interface() view public {
        // Test for implemented interfaces        
        assertTrue(resolver.supportsInterface(0x3b3b57de), "Should support addr interface");
        assertTrue(resolver.supportsInterface(0xf1cb7e06), "Should support address interface");
        assertTrue(resolver.supportsInterface(0x59d1d43c), "Should support text interface");
        assertTrue(resolver.supportsInterface(0xbc1c58d1), "Should support contenthash interface");
        assertTrue(resolver.supportsInterface(type(INameResolver).interfaceId), "Should support name interface");
        
        // Test for ERC165 interface
        assertTrue(resolver.supportsInterface(0x01ffc9a7), "Should support ERC165");
        
        // Test for unsupported interface
        assertFalse(resolver.supportsInterface(0xffffffff), "Should not support random interface");
    }

    function test_set_and_get_name() public {
        string memory testName = "test.eth";
        
        vm.startPrank(owner);
        resolver.setName(testName);
        vm.stopPrank();

        string memory retrievedName = resolver.name(TEST_NODE);
        assertEq(retrievedName, testName);
    }

    function test_cannot_set_name_if_not_owner() public {
        string memory testName = "test.eth";
        
        vm.startPrank(makeAddr("notOwner"));
        vm.expectRevert();
        resolver.setName(testName);
        vm.stopPrank();
    }

    function test_name_returns_empty_string_if_not_set() public view {
        string memory retrievedName = resolver.name(TEST_NODE);
        assertEq(retrievedName, "");
    }

    function test_name_in_multicall() public {
        vm.startPrank(owner);
        
        // Prepare test data
        string memory testName = "test.eth";
        bytes memory ethAddress = abi.encodePacked(address(0x123));
        
        // Create multicall data
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(DedicatedResolver.setName.selector, testName);
        data[1] = abi.encodeWithSelector(bytes4(keccak256("setAddr(address)")), address(0x123));
        
        // Execute multicall
        bytes[] memory results = resolver.multicall(data);
        
        // Verify results
        assertEq(resolver.name(TEST_NODE), testName, "Name not set correctly");
        assertEq(resolver.addr(TEST_NODE), payable(address(0x123)), "Address not set correctly");
        
        vm.stopPrank();
    }

    function test_multicall() public {
        vm.startPrank(owner);
        
        // Prepare test data
        bytes memory ethAddress = abi.encodePacked(address(0x123));
        string memory testKey = "url";
        string memory testValue = "https://example.com";
        bytes memory testHash = abi.encodePacked(keccak256("test"));
        
        // Create multicall data
        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeWithSelector(bytes4(keccak256("setAddr(address)")), address(0x123));
        data[1] = abi.encodeWithSelector(DedicatedResolver.setText.selector, testKey, testValue);
        data[2] = abi.encodeWithSelector(DedicatedResolver.setContenthash.selector, testHash);
        
        // Execute multicall
        bytes[] memory results = resolver.multicall(data);
        
        // Verify results
        assertEq(resolver.addr(TEST_NODE), payable(address(0x123)), "Address not set correctly");
        assertEq(resolver.text(TEST_NODE, testKey), testValue, "Text record not set correctly");
        assertEq(resolver.contenthash(TEST_NODE), testHash, "Content hash not set correctly");
        
        vm.stopPrank();
    }

    function test_multicall_reverts_if_not_owner() public {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSelector(bytes4(keccak256("setAddr(address)")), address(0x123));
        
        vm.startPrank(makeAddr("notOwner"));
        vm.expectRevert();
        resolver.multicall(data);
        vm.stopPrank();
    }

    function test_multicall_with_invalid_selector() public {
        vm.startPrank(owner);
        
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSelector(bytes4(0x12345678)); // Invalid selector
        
        vm.expectRevert();
        resolver.multicall(data);
        
        vm.stopPrank();
    }

    function test_pubkey() public {
        bytes32 x = bytes32(uint256(1));
        bytes32 y = bytes32(uint256(2));
        
        vm.startPrank(owner);
        resolver.setPubkey(x, y);
        (bytes32 retrievedX, bytes32 retrievedY) = resolver.pubkey(TEST_NODE);
        assertEq(retrievedX, x);
        assertEq(retrievedY, y);
        vm.stopPrank();
    }

    function test_abi() public {
        uint256 contentType = 1;
        bytes memory abiData = abi.encodePacked(keccak256("test"));
        
        vm.startPrank(owner);
        resolver.setABI(contentType, abiData);
        (uint256 retrievedContentType, bytes memory retrievedData) = resolver.ABI(TEST_NODE, contentType);
        assertEq(retrievedContentType, contentType);
        assertEq(retrievedData, abiData);
        vm.stopPrank();
    }

    function test_interface_implementer() public {
        bytes4 interfaceId = bytes4(keccak256("test"));
        address implementer = address(0x123);
        
        vm.startPrank(owner);
        resolver.setInterface(interfaceId, implementer);
        address retrievedImplementer = resolver.interfaceImplementer(TEST_NODE, interfaceId);
        assertEq(retrievedImplementer, implementer);
        vm.stopPrank();
    }
} 