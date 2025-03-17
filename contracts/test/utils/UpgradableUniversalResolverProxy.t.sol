// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../src/utils/UpgradableUniversalResolverProxy.sol";
import {UniversalResolver as UniversalResolverV1} from "./MockUniversalResolver.sol";
import {UniversalResolver as UniversalResolverV2} from "ens-contracts/universalResolver/UniversalResolver.sol";
import {ForwardResolutionV1} from "ens-contracts/universalResolver/ForwardResolutionV1.sol";

import {IUniversalResolver as IUniversalResolverV1} from "../../src/utils/IUniversalResolver.sol";

import {ENS} from "ens-contracts/registry/ENS.sol";

contract MockGateway {
    function handleRequest(
        bytes memory response
    ) external pure returns (bytes memory) {
        return response;
    }
}

contract ProxyTest is Test {
    address constant ADMIN = address(0x123);
    address constant USER = address(0x456);
    address constant STRANGER = address(0x789);

    UpgradableUniversalResolverProxy proxy;
    UniversalResolverV1 urV1;
    UniversalResolverV2 urV2;
    MockGateway mockGateway;

    ForwardResolutionV1 forwardResolution;

    ENS ens = ENS(0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e);

    // Mock data for tests
    bytes dnsEncodedName = hex"0365746800"; // "eth"
    bytes mockData = hex"12345678";
    string[] gatewayUrls;
    bytes32 mockNamehash = bytes32(uint256(0x1));
    address mockResolver = address(0xabc);
    uint256 mockOffset = 0;

    event Upgraded(address indexed implementation);
    event AdminRemoved(address indexed admin);

    function setUp() public {
        gatewayUrls = new string[](1);
        gatewayUrls[0] = "http://universal-offchain-resolver.local";

        vm.startPrank(ADMIN);
        forwardResolution = new ForwardResolutionV1(address(ens), gatewayUrls);

        urV1 = new UniversalResolverV1(address(ens), gatewayUrls);
        urV2 = new UniversalResolverV2(forwardResolution);
        mockGateway = new MockGateway();

        proxy = new UpgradableUniversalResolverProxy(ADMIN, address(urV1));

        urV1.transferOwnership(address(proxy));
        vm.stopPrank();
    }

    /////// Core Functionality Tests ///////
    function test_InitialState() public view {
        assertEq(proxy.admin(), ADMIN);
        assertEq(proxy.implementation(), address(urV1));
    }

    function test_ProxyFunctionality() public {
        // Test the setGatewayURLs functionality through the proxy
        string[] memory urls = new string[](1);
        urls[0] = "https://test1";

        vm.prank(ADMIN);
        proxy.setGatewayURLs(urls);

        // Verify the gateway URLs were set correctly in the V1 implementation
        assertEq(urV1.batchGatewayURLs(0), urls[0]);
    }

    function test_SupportsInterface() public view {
        // Test that supportsInterface is properly forwarded
        bool supportsIUR = proxy.supportsInterface(
            type(IUniversalResolverV1).interfaceId
        );
        bool supportsERC165 = proxy.supportsInterface(
            type(IERC165).interfaceId
        );

        // Check against what the implementation would return directly
        bool impl_supportsIUR = urV1.supportsInterface(
            type(IUniversalResolverV1).interfaceId
        );
        bool impl_supportsERC165 = urV1.supportsInterface(
            type(IERC165).interfaceId
        );

        // Verify the proxy returns the same results as the implementation
        assertEq(supportsIUR, impl_supportsIUR);
        assertEq(supportsERC165, impl_supportsERC165);
    }

    /////// Upgrade Tests ///////
    function test_SuccessfulUpgrade() public {
        vm.expectEmit(true, true, true, true);
        emit Upgraded(address(urV2));

        vm.prank(ADMIN);
        proxy.upgradeTo(address(urV2));

        assertEq(proxy.implementation(), address(urV2));
        // Admin should still be set since we're not automatically revoking
        assertEq(proxy.admin(), ADMIN);
    }

    function test_RenounceAdmin() public {
        vm.expectEmit(true, true, true, true);
        emit AdminRemoved(ADMIN);

        vm.prank(ADMIN);
        proxy.renounceAdmin();

        assertEq(proxy.admin(), address(0));
    }

    function test_UnauthorizedUpgrade() public {
        vm.prank(STRANGER);
        vm.expectRevert();
        proxy.upgradeTo(address(urV2));
    }

    function test_UnauthorizedSetGatewayURLs() public {
        string[] memory urls = new string[](1);
        urls[0] = "https://test1";

        vm.prank(STRANGER);
        vm.expectRevert();
        proxy.setGatewayURLs(urls);
    }

    /////// CCIP-Read Tests ///////

    // Test for CCIP-Read forwarding with mocked resolver
    function test_CCIPReadForwarding() public {
        // Create a mock implementation that will revert with OffchainLookup
        MockUniversalResolverWithCCIP mockImpl = new MockUniversalResolverWithCCIP();

        // Create a new proxy using the mock implementation
        vm.startPrank(ADMIN);
        UpgradableUniversalResolverProxy ccipProxy = new UpgradableUniversalResolverProxy(
                ADMIN,
                address(mockImpl)
            );
        vm.stopPrank();

        vm.expectRevert();
        ccipProxy.resolve(dnsEncodedName, mockData);
    }

    // Test callback functions work through the proxy
    function test_CallbackFunctionality() public {
        // Create a mock implementation with callbacks
        MockCallbackImplementation mockCallbackImpl = new MockCallbackImplementation();

        // Create a new proxy using the mock implementation
        vm.startPrank(ADMIN);
        UpgradableUniversalResolverProxy callbackProxy = new UpgradableUniversalResolverProxy(
                ADMIN,
                address(mockCallbackImpl)
            );
        vm.stopPrank();

        bytes memory response = hex"1234";
        bytes memory extraData = hex"5678";

        // Call the callback function through the proxy
        (bytes memory result, address resolverAddr) = callbackProxy
            .resolveSingleCallback(response, extraData);

        // Verify the callback worked correctly
        assertEq(result, bytes.concat(response, extraData));
        assertEq(resolverAddr, address(mockCallbackImpl));
    }

    // Split the large test into multiple smaller ones
    function test_ResolveMethod() public {
        // Create a controlled implementation to check all methods
        MockCompleteImplementation mockCompleteImpl = new MockCompleteImplementation();

        // Create the proxy
        vm.startPrank(ADMIN);
        UpgradableUniversalResolverProxy methodProxy = new UpgradableUniversalResolverProxy(
                ADMIN,
                address(mockCompleteImpl)
            );
        vm.stopPrank();

        // Test resolve method
        (bytes memory resolveResult, address resolveAddr) = methodProxy.resolve(
            dnsEncodedName,
            mockData
        );
        assertEq(resolveResult, bytes.concat(dnsEncodedName, mockData));
        assertEq(resolveAddr, address(mockCompleteImpl));
    }

    function test_ResolveWithGatewaysMethod() public {
        // Create a controlled implementation to check all methods
        MockCompleteImplementation mockCompleteImpl = new MockCompleteImplementation();

        // Create the proxy
        vm.startPrank(ADMIN);
        UpgradableUniversalResolverProxy methodProxy = new UpgradableUniversalResolverProxy(
                ADMIN,
                address(mockCompleteImpl)
            );
        vm.stopPrank();

        // Test resolveWithGateways method
        (bytes memory resolveGWResult, address resolveGWAddr) = methodProxy
            .resolve(dnsEncodedName, mockData, gatewayUrls);
        assertEq(resolveGWResult, bytes.concat(dnsEncodedName, mockData));
        assertEq(resolveGWAddr, address(mockCompleteImpl));
    }

    function test_FindResolverMethod() public {
        // Create a controlled implementation to check all methods
        MockCompleteImplementation mockCompleteImpl = new MockCompleteImplementation();

        // Create the proxy
        vm.startPrank(ADMIN);
        UpgradableUniversalResolverProxy methodProxy = new UpgradableUniversalResolverProxy(
                ADMIN,
                address(mockCompleteImpl)
            );
        vm.stopPrank();

        // Test findResolver method
        (address resolverResult, bytes32 namehash, uint256 offset) = methodProxy
            .findResolver(dnsEncodedName);
        assertEq(resolverResult, mockResolver);
        assertEq(namehash, mockNamehash);
        assertEq(offset, mockOffset);
    }

    function test_ReverseMethod() public {
        // Create a controlled implementation to check all methods
        MockCompleteImplementation mockCompleteImpl = new MockCompleteImplementation();

        // Create the proxy
        vm.startPrank(ADMIN);
        UpgradableUniversalResolverProxy methodProxy = new UpgradableUniversalResolverProxy(
                ADMIN,
                address(mockCompleteImpl)
            );
        vm.stopPrank();

        // Test reverse method
        (
            string memory name,
            address addr,
            address reverseResolver,
            address addrResolver
        ) = methodProxy.reverse(dnsEncodedName);
        assertEq(name, "test.eth");
        assertEq(addr, mockResolver);
        assertEq(reverseResolver, address(mockCompleteImpl));
        assertEq(addrResolver, address(mockCompleteImpl));
    }

    function test_ReverseWithGatewaysMethod() public {
        // Create a controlled implementation to check all methods
        MockCompleteImplementation mockCompleteImpl = new MockCompleteImplementation();

        // Create the proxy
        vm.startPrank(ADMIN);
        UpgradableUniversalResolverProxy methodProxy = new UpgradableUniversalResolverProxy(
                ADMIN,
                address(mockCompleteImpl)
            );
        vm.stopPrank();

        // Test reverseWithGateways method
        (
            string memory name,
            address addr,
            address reverseResolver,
            address addrResolver
        ) = methodProxy.reverse(dnsEncodedName, gatewayUrls);
        assertEq(name, "test.eth");
        assertEq(addr, mockResolver);
        assertEq(reverseResolver, address(mockCompleteImpl));
        assertEq(addrResolver, address(mockCompleteImpl));
    }

    function test_fallbackRevertsWithUnsupportedFunction() public {
        // Try to call a function that doesn't exist on the proxy
        (bool success, ) = address(proxy).call(
            abi.encodeWithSignature("nonExistentFunction()")
        );
        assertFalse(success);
    }

    // Test handling non-CCIP-Read errors from implementation
    function test_NonCCIPReadErrorForwarding() public {
        // Create a mock implementation that reverts with a custom error
        MockRevertingImplementation mockRevertImpl = new MockRevertingImplementation();

        // Create a new proxy using the mock implementation
        vm.startPrank(ADMIN);
        UpgradableUniversalResolverProxy revertProxy = new UpgradableUniversalResolverProxy(
                ADMIN,
                address(mockRevertImpl)
            );
        vm.stopPrank();

        // Verify the custom error is forwarded properly
        vm.expectRevert(
            abi.encodeWithSelector(MockRevertingImplementation.CustomError.selector)
        );
        revertProxy.resolve(dnsEncodedName, mockData);
    }

    // Test CCIP-Read case where originalSender is not the implementation address
    function test_CCIPReadWithNonImplementationSender() public {
        // Create a mock that reverts with OffchainLookup but uses a different sender
        MockUniversalResolverWithDifferentSender mockImplDiffSender = new MockUniversalResolverWithDifferentSender();

        // Create a new proxy
        vm.startPrank(ADMIN);
        UpgradableUniversalResolverProxy senderProxy = new UpgradableUniversalResolverProxy(
                ADMIN,
                address(mockImplDiffSender)
            );
        vm.stopPrank();

        // The original OffchainLookup should be forwarded without modification
        // since the sender is not the implementation
        vm.expectRevert(
            abi.encodeWithSelector(
                OffchainLookup.selector,
                mockImplDiffSender.getAlternateSender(),
                mockImplDiffSender.getUrls(),
                mockImplDiffSender.getCallData(),
                mockImplDiffSender.getCallback(),
                mockImplDiffSender.getExtraData()
            )
        );

        senderProxy.resolve(dnsEncodedName, mockData);
    }

    // Test attempting to upgrade to address with no code
    function test_UpgradeToEmptyAddress() public {
        // Try to upgrade to a non-contract address
        vm.prank(ADMIN);
        vm.expectRevert(
            UpgradableUniversalResolverProxy.InvalidImplementation.selector
        );
        proxy.upgradeTo(address(0x999)); // Address with no code
    }

    // Test edge case with returnData less than 4 bytes
    function test_ReturnDataLessThan4Bytes() public {
        // Create a mock implementation that returns short error data
        MockShortErrorImplementation mockShortImpl = new MockShortErrorImplementation();

        // Create a new proxy using the mock implementation
        vm.startPrank(ADMIN);
        UpgradableUniversalResolverProxy shortProxy = new UpgradableUniversalResolverProxy(
                ADMIN,
                address(mockShortImpl)
            );
        vm.stopPrank();

        // The error should still be forwarded correctly
        vm.expectRevert(); // Just expect any revert
        shortProxy.resolve(dnsEncodedName, mockData);
    }
}

// Base contract with default implementations for all IUniversalResolver methods
abstract contract MockUniversalResolverBase is IUniversalResolverV1 {
    // Default implementations that can be overridden by specific mock contracts
    function resolve(
        bytes calldata,
        bytes memory
    ) external view virtual returns (bytes memory, address) {
        return (bytes(""), address(0));
    }

    function resolve(
        bytes calldata,
        bytes memory,
        string[] memory
    ) external view virtual returns (bytes memory, address) {
        return (bytes(""), address(0));
    }

    function resolve(
        bytes calldata,
        bytes[] memory
    ) external view virtual returns (Result[] memory, address) {
        Result[] memory results = new Result[](0);
        return (results, address(0));
    }

    function resolve(
        bytes calldata,
        bytes[] memory,
        string[] memory
    ) external view virtual returns (Result[] memory, address) {
        Result[] memory results = new Result[](0);
        return (results, address(0));
    }

    function findResolver(
        bytes calldata
    ) external view virtual returns (address, bytes32, uint256) {
        return (address(0), bytes32(0), 0);
    }

    function reverse(
        bytes calldata
    ) external view virtual returns (string memory, address, address, address) {
        return ("", address(0), address(0), address(0));
    }

    function reverse(
        bytes calldata,
        string[] memory
    ) external view virtual returns (string memory, address, address, address) {
        return ("", address(0), address(0), address(0));
    }

    function resolveCallback(
        bytes calldata,
        bytes calldata
    ) external view virtual returns (Result[] memory, address) {
        Result[] memory results = new Result[](0);
        return (results, address(0));
    }

    function resolveSingleCallback(
        bytes calldata,
        bytes calldata
    ) external view virtual returns (bytes memory, address) {
        return (bytes(""), address(0));
    }

    function reverseCallback(
        bytes calldata,
        bytes calldata
    ) external view virtual returns (string memory, address, address, address) {
        return ("", address(0), address(0), address(0));
    }

    function setGatewayURLs(string[] memory) external virtual {
        // Default empty implementation
    }

    function supportsInterface(bytes4) external view virtual returns (bool) {
        return false;
    }
}

// Each specific mock now only needs to override the methods it's testing
contract MockUniversalResolverWithCCIP is MockUniversalResolverBase {
    string[] private urls = new string[](1);
    bytes private callData = hex"1234";
    bytes4 private callbackSelector =
        bytes4(keccak256("mockCallback(bytes,bytes)"));
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

    function getCallback() external view returns (bytes4) {
        return callbackSelector;
    }

    function getExtraData() external view returns (bytes memory) {
        return extraData;
    }

    function resolve(
        bytes calldata,
        bytes memory
    ) external view override returns (bytes memory, address) {
        // Use proper Solidity error mechanism instead of assembly
        revert OffchainLookup(
            address(this),
            urls,
            callData,
            callbackSelector,
            extraData
        );
    }
}

contract MockCallbackImplementation is MockUniversalResolverBase {
    function resolveSingleCallback(
        bytes calldata response,
        bytes calldata extraData
    ) external view override returns (bytes memory, address) {
        return (bytes.concat(response, extraData), address(this));
    }

    function reverseCallback(
        bytes calldata response,
        bytes calldata extraData
    )
        external
        view
        override
        returns (string memory, address, address, address)
    {
        return (
            string(bytes.concat(response, extraData)),
            address(this),
            address(this),
            address(this)
        );
    }
}

contract MockCompleteImplementation is MockUniversalResolverBase {
    address public constant MOCK_RESOLVER = address(0xabc);
    bytes32 public constant MOCK_NAMEHASH = bytes32(uint256(0x1));
    uint256 public constant MOCK_OFFSET = 0;

    function resolve(
        bytes calldata name,
        bytes memory data
    ) external view override returns (bytes memory, address) {
        return (bytes.concat(name, data), address(this));
    }

    function resolve(
        bytes calldata name,
        bytes memory data,
        string[] memory
    ) external view override returns (bytes memory, address) {
        return (bytes.concat(name, data), address(this));
    }

    function findResolver(
        bytes calldata
    ) external pure override returns (address, bytes32, uint256) {
        return (MOCK_RESOLVER, MOCK_NAMEHASH, MOCK_OFFSET);
    }

    function reverse(
        bytes calldata
    )
        external
        view
        override
        returns (string memory, address, address, address)
    {
        return ("test.eth", MOCK_RESOLVER, address(this), address(this));
    }

    function reverse(
        bytes calldata,
        string[] memory
    )
        external
        view
        override
        returns (string memory, address, address, address)
    {
        return ("test.eth", MOCK_RESOLVER, address(this), address(this));
    }

    function resolveSingleCallback(
        bytes calldata response,
        bytes calldata extraData
    ) external view override returns (bytes memory, address) {
        return (bytes.concat(response, extraData), address(this));
    }

    function reverseCallback(
        bytes calldata response,
        bytes calldata extraData
    )
        external
        view
        override
        returns (string memory, address, address, address)
    {
        return (
            string(bytes.concat(response, extraData)),
            address(this),
            address(this),
            address(this)
        );
    }
}

contract MockRevertingImplementation is MockUniversalResolverBase {
    error CustomError();

    function resolve(
        bytes calldata,
        bytes memory
    ) external pure override returns (bytes memory, address) {
        revert CustomError();
    }
}

contract MockUniversalResolverWithDifferentSender is MockUniversalResolverBase {
    string[] private urls = new string[](1);
    bytes private callData = hex"1234";
    bytes4 private callbackSelector =
        bytes4(keccak256("mockCallback(bytes,bytes)"));
    bytes private extraData = hex"5678";
    address private alternateSender = address(0xbeef);

    constructor() {
        urls[0] = "https://mockgateway.com";
    }

    function getUrls() external view returns (string[] memory) {
        return urls;
    }

    function getCallData() external view returns (bytes memory) {
        return callData;
    }

    function getCallback() external view returns (bytes4) {
        return callbackSelector;
    }

    function getExtraData() external view returns (bytes memory) {
        return extraData;
    }

    function getAlternateSender() external view returns (address) {
        return alternateSender;
    }

    function resolve(
        bytes calldata,
        bytes memory
    ) external view override returns (bytes memory, address) {
        // Use proper Solidity error mechanism instead of assembly
        revert OffchainLookup(
            alternateSender,
            urls,
            callData,
            callbackSelector,
            extraData
        );
    }
}

contract MockShortErrorImplementation is MockUniversalResolverBase {
    function resolve(
        bytes calldata,
        bytes memory
    ) external pure override returns (bytes memory, address) {
        revert("abc");
    }
}
