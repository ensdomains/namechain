// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

// solhint-disable no-console, private-vars-leading-underscore, state-visibility, func-name-mixedcase, namechain/ordering

import {Test, Vm} from "forge-std/Test.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {OffchainResolverMetadataProvider} from "~src/common/resolver/OffchainResolverMetadataProvider.sol";
import {IOffchainResolverMetadataProvider} from "~src/common/resolver/interfaces/IOffchainResolverMetadataProvider.sol";

/// @dev Concrete implementation of OffchainResolverMetadataProvider for testing
contract TestMetadataProvider is OffchainResolverMetadataProvider {
    constructor() Ownable(msg.sender) {}
}

contract OffchainResolverMetadataProviderTest is Test {
    TestMetadataProvider provider;
    address owner;
    address nonOwner;
    address mockBaseRegistry;

    function setUp() external {
        owner = address(this);
        nonOwner = address(0x1234);
        mockBaseRegistry = address(0xE7C1);

        provider = new TestMetadataProvider();
    }

    function test_supportsInterface_IOffchainResolverMetadataProvider() external view {
        bytes4 interfaceId = type(IOffchainResolverMetadataProvider).interfaceId;
        assertTrue(provider.supportsInterface(interfaceId));
    }

    function test_metadata_returnsDefaultValues() external view {
        (string[] memory rpcURLs, uint256 chainId, address baseRegistry) = provider.metadata(
            hex"0365746800" // "eth" DNS-encoded with null terminator
        );

        assertEq(rpcURLs.length, 0);
        assertEq(chainId, 0);
        assertEq(baseRegistry, address(0));
    }

    function test_setMetadata_setsValuesCorrectly() external {
        string[] memory rpcURLs = new string[](2);
        rpcURLs[0] = "https://rpc1.namechain.example";
        rpcURLs[1] = "https://rpc2.namechain.example";
        uint256 expectedChainId = 12345;

        provider.setMetadata(hex"0365746800", rpcURLs, expectedChainId, mockBaseRegistry);

        (string[] memory returnedURLs, uint256 returnedChainId, address baseRegistry) =
            provider.metadata(hex"0365746800");

        assertEq(returnedURLs.length, 2);
        assertEq(returnedURLs[0], "https://rpc1.namechain.example");
        assertEq(returnedURLs[1], "https://rpc2.namechain.example");
        assertEq(returnedChainId, expectedChainId);
        assertEq(baseRegistry, mockBaseRegistry);
    }

    function test_setMetadata_emitsMetadataChangedEvent() external {
        string[] memory rpcURLs = new string[](1);
        rpcURLs[0] = "https://rpc.namechain.example";
        uint256 expectedChainId = 99999;

        vm.recordLogs();

        provider.setMetadata(hex"0365746800", rpcURLs, expectedChainId, mockBaseRegistry);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);

        // Check event signature
        bytes32 expectedEventSig = keccak256("MetadataChanged(bytes,string[],uint256,address)");
        assertEq(logs[0].topics[0], expectedEventSig);

        // Decode event data
        (bytes memory name, string[] memory emittedURLs, uint256 emittedChainId, address emittedRegistry) =
            abi.decode(logs[0].data, (bytes, string[], uint256, address));

        assertEq(name, hex"0365746800"); // "eth" DNS-encoded with null terminator
        assertEq(emittedURLs.length, 1);
        assertEq(emittedURLs[0], "https://rpc.namechain.example");
        assertEq(emittedChainId, expectedChainId);
        assertEq(emittedRegistry, mockBaseRegistry);
    }

    function test_setMetadata_onlyOwner() external {
        string[] memory rpcURLs = new string[](1);
        rpcURLs[0] = "https://rpc.namechain.example";

        vm.expectRevert();
        vm.prank(nonOwner);
        provider.setMetadata(hex"0365746800", rpcURLs, 12345, mockBaseRegistry);
    }

    function test_chainId_returnsStoredValue() external {
        string[] memory rpcURLs = new string[](0);
        uint256 expectedChainId = 31338;

        provider.setMetadata(hex"0365746800", rpcURLs, expectedChainId, mockBaseRegistry);

        assertEq(provider.chainId(), expectedChainId);
    }

    function test_metadata_withEmptyRpcURLs() external {
        string[] memory rpcURLs = new string[](0);
        uint256 expectedChainId = 42;

        provider.setMetadata(hex"0365746800", rpcURLs, expectedChainId, mockBaseRegistry);

        (string[] memory returnedURLs, uint256 returnedChainId,) = provider.metadata(hex"0365746800");

        assertEq(returnedURLs.length, 0);
        assertEq(returnedChainId, expectedChainId);
    }

    function test_baseRegistry_returnsStoredValue() external {
        string[] memory rpcURLs = new string[](0);

        provider.setMetadata(hex"0365746800", rpcURLs, 0, mockBaseRegistry);

        assertEq(provider.baseRegistry(), mockBaseRegistry);
    }
}
