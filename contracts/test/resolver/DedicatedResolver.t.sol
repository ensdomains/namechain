// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {DedicatedResolver} from "../../src/common/DedicatedResolver.sol";
import {VerifiableFactory} from "@ensdomains/verifiable-factory/VerifiableFactory.sol";
import {UUPSProxy} from "@ensdomains/verifiable-factory/UUPSProxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {INameResolver} from "@ens/contracts/resolvers/profiles/INameResolver.sol";
import {console} from "forge-std/console.sol";

interface IUniversalResolverV2 {
    function findResolver(string memory name) external view returns (address);
}

contract DedicatedResolverTest is Test {
    VerifiableFactory factory;
    uint256 constant SALT = 12345;
    address public owner;
    DedicatedResolver resolver;
    uint256 constant ETH_COIN_TYPE = 60;
    bytes32 constant TEST_NODE = bytes32(uint256(1)); // Test node for getter functions
    address public universalResolver;
    address public alice;

    function setUp() public {
        owner = makeAddr("owner");
        factory = new VerifiableFactory();
        
        address implementation = address(new DedicatedResolver());
        bytes memory initData = abi.encodeWithSelector(
            DedicatedResolver.initialize.selector,
            owner,
            true, // wildcard
            address(0x456) // universalResolver
        );
        vm.startPrank(owner);
        address deployed = factory.deployProxy(implementation, SALT, initData);
        vm.stopPrank();
        
        resolver = DedicatedResolver(deployed);
        universalResolver = address(0x456);
        alice = makeAddr("alice");
    }

    function test_deploy() public view {
        UUPSProxy proxy = UUPSProxy(payable(address(resolver)));
        bytes32 outerSalt = keccak256(abi.encode(owner, SALT));
        assertEq(proxy.getVerifiableProxySalt(), outerSalt);
        assertEq(resolver.owner(), owner);
        assertTrue(resolver.wildcard(), "Wildcard should be true");
        assertEq(resolver.universalResolver(), address(0x456), "Universal resolver address should match");
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

    function test_set_universal_resolver() public {
        address newUniversalResolver = address(0x789);
        
        vm.startPrank(owner);
        resolver.setUniversalResolver(newUniversalResolver);
        vm.stopPrank();

        assertEq(resolver.universalResolver(), newUniversalResolver, "Universal resolver address should be updated");
    }

    function test_cannot_set_universal_resolver_if_not_owner() public {
        address newUniversalResolver = address(0x789);
        
        vm.startPrank(makeAddr("notOwner"));
        vm.expectRevert();
        resolver.setUniversalResolver(newUniversalResolver);
        vm.stopPrank();
    }

    function test_Addr_WithWildcardEnabled() public {
        // Deploy a new resolver instance
        address implementation = address(new DedicatedResolver());
        bytes memory initData = abi.encodeWithSelector(
            DedicatedResolver.initialize.selector,
            owner,
            true, // wildcard
            address(universalResolver)
        );
        vm.startPrank(owner);
        address deployed = factory.deployProxy(implementation, SALT + 1, initData);
        DedicatedResolver testResolver = DedicatedResolver(deployed);
        testResolver.setAddr(alice);
        vm.stopPrank();

        // Should return stored address regardless of UniversalResolver state
        vm.mockCall(
            address(universalResolver),
            abi.encodeWithSelector(IUniversalResolverV2.findResolver.selector, "test.eth"),
            abi.encode(address(testResolver))
        );
        assertEq(testResolver.addr(bytes32(0)), alice);

        vm.mockCall(
            address(universalResolver),
            abi.encodeWithSelector(IUniversalResolverV2.findResolver.selector, "test.eth"),
            abi.encode(address(1))
        );
        assertEq(testResolver.addr(bytes32(0)), alice);
    }

    function test_Addr_WithWildcardDisabled() public {
        console.log("Starting test_Addr_WithWildcardDisabled");
        
        // Deploy a new resolver instance
        console.log("Deploying new resolver instance");
        address implementation = address(new DedicatedResolver());
        bytes memory initData = abi.encodeWithSelector(
            DedicatedResolver.initialize.selector,
            owner,
            false, // wildcard
            address(universalResolver)
        );
        vm.startPrank(owner);
        console.log("Deploying proxy");
        address deployed = factory.deployProxy(implementation, SALT + 2, initData);
        DedicatedResolver testResolver = DedicatedResolver(deployed);
        console.log("Setting name to test.eth");
        testResolver.setName("test.eth");
        console.log("Setting addr to alice");
        testResolver.setAddr(alice);
        vm.stopPrank();

        // Verify initial state
        console.log("Verifying initial state");
        assertFalse(testResolver.wildcard(), "Wildcard should be false");
        assertEq(testResolver.universalResolver(), address(universalResolver), "Universal resolver address should match");

        // Should return stored address when this resolver is the current resolver
        console.log("Testing when resolver is current resolver");
        vm.mockCall(
            address(universalResolver),
            abi.encodeWithSelector(IUniversalResolverV2.findResolver.selector, "test.eth"),
            abi.encode(address(testResolver))
        );
        address result = testResolver.addr(bytes32(0));
        assertEq(result, alice, "Should return alice when resolver is current resolver");

        // Should return zero address when this resolver is not the current resolver
        console.log("Testing when resolver is not current resolver");
        vm.mockCall(
            address(universalResolver),
            abi.encodeWithSelector(IUniversalResolverV2.findResolver.selector, "test.eth"),
            abi.encode(address(1))
        );
        result = testResolver.addr(bytes32(0));
        assertEq(result, address(0), "Should return zero address when resolver is not current resolver");
        console.log("Test completed successfully");
    }

    function test_Addr_WithWildcardDisabled_NoUniversalResolver() public {
        console.log("Starting test_Addr_WithWildcardDisabled_NoUniversalResolver");
        
        // Deploy a new resolver instance
        console.log("Deploying new resolver instance");
        address implementation = address(new DedicatedResolver());
        bytes memory initData = abi.encodeWithSelector(
            DedicatedResolver.initialize.selector,
            owner,
            false, // wildcard
            address(0) // no universal resolver
        );
        vm.startPrank(owner);
        console.log("Deploying proxy");
        address deployed = factory.deployProxy(implementation, SALT + 3, initData);
        DedicatedResolver testResolver = DedicatedResolver(deployed);
        console.log("Setting name to test.eth");
        testResolver.setName("test.eth");
        console.log("Setting addr to alice");
        testResolver.setAddr(alice);
        vm.stopPrank();

        // Verify initial state
        console.log("Verifying initial state");
        assertFalse(testResolver.wildcard(), "Wildcard should be false");
        assertEq(testResolver.universalResolver(), address(0), "Universal resolver should be zero address");

        // Should return zero address when UniversalResolver is not set
        console.log("Testing addr with no UniversalResolver");
        address result = testResolver.addr(bytes32(0));
        assertEq(result, address(0), "Should return zero address when UniversalResolver is not set");
        console.log("Test completed successfully");
    }
} 