// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @dev CCIP-Read error
 */
error OffchainLookup(
    address sender,
    string[] urls,
    bytes callData,
    bytes4 callbackFunction,
    bytes extraData
);

/**
 * @dev Result structure for resolve methods that return multiple results
 */
struct Result {
    bool success;
    bytes returnData;
}

/**
 * @title IUniversalResolver
 * @dev Interface for UniversalResolver matching the V1 implementation
 */
interface IUniversalResolver {
    // Core resolution methods
    function resolve(bytes calldata name, bytes memory data) external view returns (bytes memory, address);
    function resolve(bytes calldata name, bytes memory data, string[] memory gateways) external view returns (bytes memory, address);
    function resolve(bytes calldata name, bytes[] memory data) external view returns (Result[] memory, address);
    function resolve(bytes calldata name, bytes[] memory data, string[] memory gateways) external view returns (Result[] memory, address);
    
    // Reverse resolution methods
    function reverse(bytes calldata reverseName) external view returns (string memory, address, address, address);
    function reverse(bytes calldata reverseName, string[] memory gateways) external view returns (string memory, address, address, address);
    
    // Callback functions
    function resolveCallback(bytes calldata response, bytes calldata extraData) external view returns (Result[] memory, address);
    function resolveSingleCallback(bytes calldata response, bytes calldata extraData) external view returns (bytes memory, address);
    function reverseCallback(bytes calldata response, bytes calldata extraData) external view returns (string memory, address, address, address);
    
    // Resolver finding
    function findResolver(bytes calldata name) external view returns (address, bytes32, uint256);
    
    // Gateway management
    function setGatewayURLs(string[] memory urls) external;
}
