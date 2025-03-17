// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/StorageSlot.sol";

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IUniversalResolver as IUniversalResolverV2} from "ens-contracts/universalResolver/IUniversalResolver.sol";
import {OffchainLookup} from "ens-contracts/ccipRead/EIP3668.sol";
import {CCIPReader} from "ens-contracts/ccipRead/CCIPReader.sol";

import {IUniversalResolver as IUniversalResolverV1, Result} from "./IUniversalResolver.sol";

/**
 * @title UpgradableUniversalResolverProxy
 * @dev A specialized proxy for UniversalResolver that forwards method calls
 * and properly handles CCIP-Read reverts. Admin can upgrade the implementation.
 */
contract UpgradableUniversalResolverProxy is IUniversalResolverV1, IUniversalResolverV2, CCIPReader {
    // Storage slot for implementation address (EIP-1967 compatible)
    bytes32 private constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // Storage slot for admin (EIP-1967 compatible)
    bytes32 private constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    // Custom errors
    error CallerNotAdmin();
    error InvalidImplementation();
    error UnsupportedFunction();
    error SameImplementation();

    // Events
    event Upgraded(address indexed implementation);
    event AdminChanged(address indexed previousAdmin, address indexed newAdmin);
    event AdminRemoved(address indexed admin);

    /**
     * @dev Initializes the proxy with an implementation and admin.
     * @param admin_ The address of the admin
     * @param implementation_ The address of the implementation
     */
    constructor(address admin_, address implementation_) {
        _validateImplementation(implementation_);
        _setImplementation(implementation_);
        _setAdmin(admin_);
    }

    /**
     * @dev Modifier restricting a function to the admin.
     */
    modifier onlyAdmin() {
        if (msg.sender != _getAdmin()) revert CallerNotAdmin();
        _;
    }

    /**
     * @dev Upgrades to a new implementation.
     * @param newImplementation Address of the new implementation
     */
    function upgradeTo(address newImplementation) external onlyAdmin {
        _validateImplementation(newImplementation);
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    /**
     * @dev Allows admin to revoke their admin rights by setting admin to address(0).
     */
    function renounceAdmin() external onlyAdmin {
        address admin_ = _getAdmin();
        _setAdmin(address(0));
        emit AdminRemoved(admin_);
    }

    /**
     * @dev Returns the current implementation address.
     */
    function implementation() external view returns (address) {
        return _getImplementation();
    }

    /**
     * @dev Returns the current admin address.
     */
    function admin() external view returns (address) {
        return _getAdmin();
    }

    /**
     * @dev Validates if the implementation is valid.
     */
    function _validateImplementation(address newImplementation) internal view {
        if (newImplementation.code.length == 0) revert InvalidImplementation();
        if (_getImplementation() == newImplementation) {
            revert SameImplementation();
        }
    }

    /**
     * @dev Sets the implementation address in storage.
     */
    function _setImplementation(address newImplementation) private {
        StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
    }

    /**
     * @dev Gets the current implementation address from storage.
     */
    function _getImplementation() internal view returns (address) {
        return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
    }

    /**
     * @dev Sets the admin address in storage.
     */
    function _setAdmin(address newAdmin) private {
        address previousAdmin = _getAdmin();
        StorageSlot.getAddressSlot(_ADMIN_SLOT).value = newAdmin;
        emit AdminChanged(previousAdmin, newAdmin);
    }

    /**
     * @dev Gets the current admin address from storage.
     */
    function _getAdmin() internal view returns (address) {
        return StorageSlot.getAddressSlot(_ADMIN_SLOT).value;
    }

    /**
     * @dev Calls the implementation with CCIP-Read error handling
     * Uses MCOPY opcode (EIP-5656) for memory copying
     */
    function _callImplementationWithCCIP(bytes memory callData) internal view returns (bytes memory) {
        address implementationAddress = _getImplementation();

        // Low-level call to handle CCIP-Read reverts
        (bool success, bytes memory returnData) = implementationAddress.staticcall(callData);

        if (!success) {
            // Check if this is a CCIP-Read revert
            if (returnData.length >= 4) {
                // Extract the selector using assembly
                bytes4 selector;
                assembly {
                    selector := mload(add(returnData, 32))
                }

                if (selector == OffchainLookup.selector) {
                    // Create a properly formatted bytes array for abi.decode
                    // by skipping the first 4 bytes (the selector)
                    bytes memory encodedParams = new bytes(returnData.length - 4);

                    // Copy the parameters (skipping the selector)
                    assembly {
                        // Copy all bytes except the first 4
                        let lenParams := sub(mload(returnData), 4)
                        let srcParams := add(add(returnData, 32), 4) // source: returnData + 32 (length field) + 4 (selector)
                        let destParams := add(encodedParams, 32) // destination: encodedParams + 32 (length field)

                        mcopy(destParams, srcParams, lenParams)
                    }

                    // Now decode the parameters
                    (
                        address originalSender,
                        string[] memory urls,
                        bytes memory ccipCallData,
                        bytes4 callbackFunction,
                        bytes memory extraData
                    ) = abi.decode(encodedParams, (address, string[], bytes, bytes4, bytes));

                    // Ensure that the sender is us (the proxy), not the implementation
                    if (originalSender == implementationAddress) {
                        // Revert with a modified OffchainLookup error using this contract as sender
                        revert OffchainLookup(address(this), urls, ccipCallData, callbackFunction, extraData);
                    }
                }
            }

            // For any other revert, just pass it through
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }

        return returnData;
    }

    /**
     * @dev Implements supportsInterface - forwards to implementation
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        // Direct forwarding without CCIP-Read handling
        return IERC165(_getImplementation()).supportsInterface(interfaceId);
    }

    /**
     * @dev Allows admin to set gateway URLs
     */
    function setGatewayURLs(string[] memory urls) external onlyAdmin {
        IUniversalResolverV1(_getImplementation()).setGatewayURLs(urls);
    }

    /**
     * @dev IUniversalResolver implementation - with CCIP-Read handling
     */
    function resolve(bytes calldata name, bytes memory data) external view override(IUniversalResolverV1, IUniversalResolverV2) returns (bytes memory, address) {
        bytes memory result =
            _callImplementationWithCCIP(abi.encodeWithSelector(bytes4(keccak256("resolve(bytes,bytes[])")), name, data));
        return abi.decode(result, (bytes, address));
    }

    function resolve(bytes calldata name, bytes memory data, string[] memory gateways)
        external
        view
        returns (bytes memory, address)
    {
        bytes memory result = _callImplementationWithCCIP(
            abi.encodeWithSelector(bytes4(keccak256("resolve(bytes,bytes[])")), name, data, gateways)
        );
        return abi.decode(result, (bytes, address));
    }

    function resolve(bytes calldata name, bytes[] memory data) external view returns (Result[] memory, address) {
        bytes memory result = _callImplementationWithCCIP(
            abi.encodeWithSelector(bytes4(keccak256("resolve(bytes,bytes[])")), name, data)
        );
        return abi.decode(result, (Result[], address));
    }

    function resolve(bytes calldata name, bytes[] memory data, string[] memory gateways) external view returns (Result[] memory, address) {
        bytes memory result = _callImplementationWithCCIP(
            abi.encodeWithSelector(bytes4(keccak256("resolve(bytes,bytes[],string[])")), name, data, gateways)
        );
        return abi.decode(result, (Result[], address));
    }

    function resolveCallback(bytes calldata response, bytes calldata extraData) external view returns (Result[] memory, address) {
        bytes memory result = _callImplementationWithCCIP(
            abi.encodeWithSelector(IUniversalResolverV1.resolveCallback.selector, response, extraData)
        );
        return abi.decode(result, (Result[], address));
    }

    function findResolver(bytes calldata name) external view returns (address, bytes32, uint256) {
        // This method doesn't use CCIP-Read, so direct forwarding is fine
        return IUniversalResolverV1(_getImplementation()).findResolver(name);
    }

    function reverse(bytes calldata reverseName) external view returns (string memory, address, address, address) {
        bytes memory result =
            _callImplementationWithCCIP(abi.encodeWithSelector(bytes4(keccak256("reverse(bytes)")), reverseName));
        return abi.decode(result, (string, address, address, address));
    }

    function reverse(bytes calldata reverseName, string[] memory gateways) external view returns (string memory, address, address, address) {
        bytes memory result = _callImplementationWithCCIP(
            abi.encodeWithSelector(bytes4(keccak256("reverse(bytes,string[])")), reverseName, gateways)
        );
        return abi.decode(result, (string, address, address, address));
    }

    function reverse(bytes calldata lookupAddress, uint256 coinType) external view returns (string memory primary, address resolver, address reverseResolver) {
        bytes memory result = _callImplementationWithCCIP(
            abi.encodeWithSelector(bytes4(keccak256("reverse(bytes,uint256)")), lookupAddress, coinType)
        );
        return abi.decode(result, (string, address, address));
    }

    function resolveSingleCallback(bytes calldata response, bytes calldata extraData)
        external
        view
        returns (bytes memory, address)
    {
        bytes memory result = _callImplementationWithCCIP(
            abi.encodeWithSelector(IUniversalResolverV1.resolveSingleCallback.selector, response, extraData)
        );
        return abi.decode(result, (bytes, address));
    }

    function reverseCallback(bytes calldata response, bytes calldata extraData)
        external
        view
        returns (string memory, address, address, address)
    {
        bytes memory result = _callImplementationWithCCIP(
            abi.encodeWithSelector(IUniversalResolverV1.reverseCallback.selector, response, extraData)
        );
        return abi.decode(result, (string, address, address, address));
    }

    /**
     * @dev Fallback function for any methods not explicitly mapped
     */
    fallback() external payable {
        revert UnsupportedFunction();
    }

    /**
     * @dev Receive function for plain Ether transfers
     */
    receive() external payable {}
}
