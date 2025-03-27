// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../src/utils/UpgradableUniversalResolverProxy.sol";

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {ENS} from "ens-contracts/registry/ENS.sol";
import {EIP3668, OffchainLookup} from "ens-contracts/ccipRead/EIP3668.sol";

import {IUniversalResolver as IUniversalResolverV1} from "ens-contracts/universalResolver/IUniversalResolver.sol";
import {UniversalResolver as UniversalResolverV1} from "ens-contracts/universalResolver/UniversalResolver.sol";
import {UniversalResolver as UniversalResolverV2} from "../../src/utils/UniversalResolver.sol";
import {IRegistry} from "../../src/registry/IRegistry.sol";
import {BaseRegistry} from "../../src/registry/BaseRegistry.sol";



contract ProxyTest is Test {
    address constant ADMIN = address(0x123);
    address constant USER = address(0x456);
    address constant STRANGER = address(0x789);

    UpgradableUniversalResolverProxy proxy;
    UniversalResolverV1 urV1;
    UniversalResolverV2 urV2;

    ENS ens = ENS(0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e);

    // Mock data for tests
    bytes dnsEncodedName = hex"0365746800"; // "eth"
    bytes mockData = hex"12345678";
    string[] gatewayUrls;
    bytes32 mockNamehash = bytes32(uint256(0x1));
    address mockResolver = address(0xabc);
    uint256 mockOffset = 0;

    event Upgraded(address indexed implementation);
    event AdminChanged(address indexed previousAdmin, address indexed newAdmin);
    event AdminRemoved(address indexed admin);

    function setUp() public {
        gatewayUrls = new string[](1);
        gatewayUrls[0] = "http://universal-offchain-resolver.local";

        vm.startPrank(ADMIN);

        // Deploy the implementations
        urV1 = new UniversalResolverV1(ens, gatewayUrls);
        urV2 = new UniversalResolverV2(IRegistry(address(ens)));

        // Deploy the proxy with V1 implementation
        proxy = new UpgradableUniversalResolverProxy(ADMIN, address(urV1));

        vm.stopPrank();
    }

    /////// Core Functionality Tests ///////
    
    function test_InitialState() public view {
        assertEq(proxy.admin(), ADMIN);
        assertEq(proxy.implementation(), address(urV1));
    }

    // function test_SupportsInterface() public view {
    //     // Test that supportsInterface is properly forwarded
    //     bool supportsIUR = proxy.supportsInterface(
    //         type(IUniversalResolverV1).interfaceId
    //     );
    //     bool supportsERC165 = proxy.supportsInterface(
    //         type(IERC165).interfaceId
    //     );

    //     // Verify that the proxy returns the expected results
    //     // assuming V1 implementation supports these interfaces
    //     assertTrue(supportsIUR);
    //     assertTrue(supportsERC165);
    // }

    /////// Admin Tests ///////
    
    function test_SuccessfulUpgrade() public {
        // Expect the Upgraded event to be emitted
        vm.expectEmit(true, true, true, true);
        emit Upgraded(address(urV2));

        // Perform the upgrade
        vm.prank(ADMIN);
        proxy.upgradeTo(address(urV2));

        // Verify the implementation was updated
        assertEq(proxy.implementation(), address(urV2));
        // Admin should remain unchanged
        assertEq(proxy.admin(), ADMIN);
    }

    function test_RenounceAdmin() public {
        // Expect AdminRemoved event
        vm.expectEmit(true, true, true, true);
        emit AdminRemoved(ADMIN);

        // Perform admin renouncement
        vm.prank(ADMIN);
        proxy.renounceAdmin();

        // Verify admin was removed
        assertEq(proxy.admin(), address(0));
    }

    function test_UnauthorizedUpgrade() public {
        // Try to upgrade from non-admin account
        vm.prank(STRANGER);
        vm.expectRevert(UpgradableUniversalResolverProxy.CallerNotAdmin.selector);
        proxy.upgradeTo(address(urV2));
    }

    function test_UpgradeToInvalidImplementation() public {
        // Try to upgrade to a non-contract address
        vm.prank(ADMIN);
        vm.expectRevert(UpgradableUniversalResolverProxy.InvalidImplementation.selector);
        proxy.upgradeTo(address(0));

        // Try to upgrade to the same implementation
        vm.prank(ADMIN);
        vm.expectRevert(UpgradableUniversalResolverProxy.SameImplementation.selector);
        proxy.upgradeTo(address(urV1));
    }

    // function test_UpgradeToNonUniversalResolver() public {
    //     // Deploy a contract that doesn't implement IUniversalResolver
    //     MockNonUniversalResolver nonUR = new MockNonUniversalResolver();

    //     // Try to upgrade to that contract
    //     vm.prank(ADMIN);
    //     vm.expectRevert(UpgradableUniversalResolverProxy.InvalidImplementation.selector);
    //     proxy.upgradeTo(address(nonUR));
    // }

    /////// Forwarding Tests ///////
    
    function test_ForwardingSingleCall() public {
        // Test with a mock implementation that returns predefined values
        MockCompleteImplementation mockImpl = new MockCompleteImplementation();
        
        // Create a new proxy with the mock implementation
        vm.prank(ADMIN);
        UpgradableUniversalResolverProxy testProxy = new UpgradableUniversalResolverProxy(
            ADMIN,
            address(mockImpl)
        );
        
        // Call resolve method
        (bytes memory result, address resolverAddr) = testProxy.resolve(
            dnsEncodedName,
            mockData
        );
        
        // Verify the correct values were returned
        assertEq(result, bytes.concat(dnsEncodedName, mockData));
        assertEq(resolverAddr, mockResolver);
    }

    function test_ForwardingReverseCall() public {
        // Test with a mock implementation that returns predefined values
        MockCompleteImplementation mockImpl = new MockCompleteImplementation();
        
        // Create a new proxy with the mock implementation
        vm.prank(ADMIN);
        UpgradableUniversalResolverProxy testProxy = new UpgradableUniversalResolverProxy(
            ADMIN,
            address(mockImpl)
        );
        
        // Call reverse method
        (
            string memory name,
            address resolver,
            address reverseResolver
        ) = testProxy.reverse(dnsEncodedName, 60);
        
        // Verify the correct values were returned
        assertEq(name, "test.eth");
        assertEq(resolver, mockResolver);
        assertEq(reverseResolver, address(mockImpl));
    }

    /////// CCIP-Read Tests ///////
    
    function test_CCIPReadForwarding() public {
        // Create a mock implementation that reverts with OffchainLookup
        MockCCIPReadImplementation mockCCIPImpl = new MockCCIPReadImplementation();
        
        // Create a new proxy using the mock implementation
        vm.prank(ADMIN);
        UpgradableUniversalResolverProxy ccipProxy = new UpgradableUniversalResolverProxy(
            ADMIN,
            address(mockCCIPImpl)
        );
        
        // Expect the OffchainLookup revert with adjusted sender
        vm.expectRevert(
            abi.encodeWithSelector(
                OffchainLookup.selector,
                address(ccipProxy),  // Sender should be the proxy, not the implementation
                mockCCIPImpl.getUrls(),
                mockCCIPImpl.getCallData(),
                mockCCIPImpl.getCallbackFunction(),
                mockCCIPImpl.getExtraData()
            )
        );
        
        // Call resolve which should trigger the CCIP-Read revert
        ccipProxy.resolve(dnsEncodedName, mockData);
    }

    function test_CCIPReadWithDifferentSender() public {
        // Create a mock implementation that reverts with OffchainLookup but with a different sender
        MockCCIPReadWithDifferentSender mockDiffSenderImpl = new MockCCIPReadWithDifferentSender();
        
        // Create a new proxy using the mock implementation
        vm.prank(ADMIN);
        UpgradableUniversalResolverProxy senderProxy = new UpgradableUniversalResolverProxy(
            ADMIN,
            address(mockDiffSenderImpl)
        );
        
        // The call should revert with the original error, not a modified one
        // Since the implementation's OffchainLookup doesn't use itself as sender
        vm.expectRevert();
        senderProxy.resolve(dnsEncodedName, mockData);
    }

    function test_NonCCIPReadErrorForwarding() public {
        // Create a mock implementation that reverts with a custom error
        MockRevertingImplementation mockRevertImpl = new MockRevertingImplementation();
        
        // Create a new proxy using the mock implementation
        vm.prank(ADMIN);
        UpgradableUniversalResolverProxy revertProxy = new UpgradableUniversalResolverProxy(
            ADMIN,
            address(mockRevertImpl)
        );
        
        // Verify the custom error is forwarded properly
        vm.expectRevert(MockRevertingImplementation.CustomError.selector);
        revertProxy.resolve(dnsEncodedName, mockData);
    }

    /////// Fallback Tests ///////
    
    function test_FallbackWithValidCall() public {
        // Test with a mock implementation that returns predefined values
        MockCompleteImplementation mockImpl = new MockCompleteImplementation();
        
        // Create a new proxy with the mock implementation
        vm.prank(ADMIN);
        UpgradableUniversalResolverProxy testProxy = new UpgradableUniversalResolverProxy(
            ADMIN,
            address(mockImpl)
        );
        
        // Create calldata for a method that is properly implemented in mock
        // Using resolve instead of resolveCallback
        bytes memory callData = abi.encodeWithSignature(
            "resolve(bytes,bytes)",
            dnsEncodedName,
            mockData
        );
        
        // Make the call through the fallback
        (bool success, bytes memory result) = address(testProxy).call(callData);
        
        // Verify the call was successful
        assertTrue(success);
        // Can't easily verify the exact result, but can check it's not empty
        assertTrue(result.length > 0);
    }

    function test_FallbackWithInvalidCall() public {
        // Create calldata for a non-existent method
        bytes memory callData = abi.encodeWithSignature("nonExistentFunction()");
        
        // The call should fail
        (bool success, ) = address(proxy).call(callData);
        assertFalse(success);
    }
}

contract MockNonUniversalResolver {
    // This contract doesn't implement IUniversalResolver
    
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}

// Base contract for mocks to implement common functionality
abstract contract UniversalResolverMockBase is IUniversalResolverV1 {
    function supportsInterface(bytes4 interfaceId) external pure virtual returns (bool) {
        return 
            interfaceId == type(IUniversalResolverV1).interfaceId || 
            interfaceId == type(IERC165).interfaceId;
    }
    
    // Default implementation for all methods
    function resolve(bytes calldata, bytes calldata) external view virtual returns (bytes memory, address) {
        return (bytes(""), address(0));
    }
    
    function findResolver(bytes calldata) external view virtual returns (address, bytes32, uint256) {
        return (address(0), bytes32(0), 0);
    }
    
    function reverse(bytes calldata, uint256) external view virtual returns (string memory, address, address) {
        return ("", address(0), address(0));
    }
}

// Mock with full implementation returning expected values
contract MockCompleteImplementation is UniversalResolverMockBase {
    address public constant MOCK_RESOLVER = address(0xabc);
    bytes32 public constant MOCK_NAMEHASH = bytes32(uint256(0x1));
    uint256 public constant MOCK_OFFSET = 0;
    
    // Add this method to handle the resolveCallback
    function resolveCallback(bytes calldata response, bytes calldata extraData) 
        external 
        pure 
        returns (bytes memory, address) 
    {
        return (bytes.concat(response, extraData), MOCK_RESOLVER);
    }
    
    function resolve(bytes calldata name, bytes calldata data) external pure override returns (bytes memory, address) {
        return (bytes.concat(name, data), MOCK_RESOLVER);
    }
    
    function findResolver(bytes calldata) external pure override returns (address, bytes32, uint256) {
        return (MOCK_RESOLVER, MOCK_NAMEHASH, MOCK_OFFSET);
    }
    
    function reverse(bytes calldata, uint256) external view override returns (string memory, address, address) {
        return ("test.eth", MOCK_RESOLVER, address(this));
    }
}

// Mock that reverts with CCIP-Read
contract MockCCIPReadImplementation is UniversalResolverMockBase {
    string[] private urls = new string[](1);
    bytes private callData = hex"1234";
    bytes4 private callbackFunction = bytes4(keccak256("mockCallback(bytes,bytes)"));
    bytes private extraData = hex"5678";
    
    constructor() {
        urls[0] = "https://mockgateway.com";
    }
    
    function getUrls() external view returns (string[] memory) {
        return urls;
    }
    
    function getCallData() external view returns (bytes memory) {
        return callData;
    }
    
    function getCallbackFunction() external view returns (bytes4) {
        return callbackFunction;
    }
    
    function getExtraData() external view returns (bytes memory) {
        return extraData;
    }
    
    function resolve(bytes calldata, bytes calldata) external view override returns (bytes memory, address) {
        // Revert with OffchainLookup
        revert OffchainLookup(
            address(this),
            urls,
            callData,
            callbackFunction,
            extraData
        );
    }
}

// Mock that reverts with CCIP-Read but uses a different sender
contract MockCCIPReadWithDifferentSender is UniversalResolverMockBase {
    address private differentSender = address(0xbeef);
    string[] private urls = new string[](1);
    bytes private callData = hex"1234";
    bytes4 private callbackFunction = bytes4(keccak256("mockCallback(bytes,bytes)"));
    bytes private extraData = hex"5678";
    
    constructor() {
        urls[0] = "https://mockgateway.com";
    }
    
    function getUrls() external view returns (string[] memory) {
        return urls;
    }
    
    function getCallData() external view returns (bytes memory) {
        return callData;
    }
    
    function getCallbackFunction() external view returns (bytes4) {
        return callbackFunction;
    }
    
    function getExtraData() external view returns (bytes memory) {
        return extraData;
    }
    
    function resolve(bytes calldata, bytes calldata) external view override returns (bytes memory, address) {
        // Revert with OffchainLookup using a different sender
        revert OffchainLookup(
            differentSender,
            urls,
            callData,
            callbackFunction,
            extraData
        );
    }
}

// Mock that reverts with a custom error
contract MockRevertingImplementation is UniversalResolverMockBase {
    error CustomError();
    
    function resolve(bytes calldata, bytes calldata) external pure override returns (bytes memory, address) {
        revert CustomError();
    }
}