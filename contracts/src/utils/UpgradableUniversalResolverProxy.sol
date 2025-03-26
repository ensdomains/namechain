// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/StorageSlot.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

// V2 Imports
import {IUniversalResolver as IUniversalResolverV2} from "ens-contracts/universalResolver/IUniversalResolver.sol";
import {UniversalResolver as UniversalResolverV2} from "ens-contracts/universalResolver/UniversalResolver.sol";

// V1 Imports
import {IUniversalResolver as IUniversalResolverV1, Result} from "./IUniversalResolverV1.sol";

// CCIP-Read Imports
import {OffchainLookup} from "ens-contracts/ccipRead/EIP3668.sol";
import {CCIPReader} from "ens-contracts/ccipRead/CCIPReader.sol";

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
    error SameImplementation();
    error FunctionNotSupported(); // For fallback

    // Events
    event Upgraded(address indexed implementation);
    event AdminChanged(address indexed previousAdmin, address indexed newAdmin);
    event AdminRemoved(address indexed admin);

    /**
     * @dev Initializes the proxy with an implementation and admin.
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

    // --- Admin Functions ---

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
     * @dev Allows admin to set gateway URLs (V1 specific function).
     * Makes an external call to the implementation.
     * @notice This function will likely revert if the current implementation is V2.
     */
    function setGatewayURLs(string[] memory urls) external override onlyAdmin {
        address impl = _getImplementation();
        require(impl != address(0), "Proxy: No implementation set");
        // Direct external call - No CCIP read expected for this admin function
        IUniversalResolverV1(impl).setGatewayURLs(urls);
    }

    // --- Internal Admin/Implementation Logic ---

    /**
     * @dev Validates if the implementation is valid.
     */
    function _validateImplementation(address newImplementation) internal view {
        if (newImplementation == address(0) || newImplementation.code.length == 0) {
             revert InvalidImplementation();
        }
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

    // --- Universal Resolver Methods (V1 & V2) ---
    // Each function makes an external call to the implementation, wrapped by ccipRead.

    // V2 `resolve(bytes, bytes)` signature (also matches V1 simple resolve)
    function resolve(bytes calldata name, bytes calldata data)
        external
        view
        override(IUniversalResolverV1, IUniversalResolverV2)
        returns (bytes memory, address)
    {
        ccipRead(_getImplementation(),abi.encodeWithSelector(IUniversalResolverV2.resolve.selector, name, data));
    }

    // V1 `resolve(bytes, bytes, string[])` signature
    function resolve(bytes calldata name, bytes memory data, string[] memory gateways)
        external
        view
        override(IUniversalResolverV1)
        returns (bytes memory, address)
    {
        // Note: This will likely revert if the implementation is V2
        ccipRead(
            _getImplementation(),
            abi.encodeWithSelector(bytes4(keccak256("resolve(bytes,bytes,string[])")), name, data, gateways)
        );
    }

    // V1 `resolve(bytes, bytes[])` signature
    function resolve(bytes calldata name, bytes[] memory data)
        external
        view
        override(IUniversalResolverV1)
        returns (Result[] memory, address)
    {
         ccipRead(
             _getImplementation(),
             abi.encodeWithSelector(bytes4(keccak256("resolve(bytes,bytes[])")), name, data)
         );
    }

    // V1 `resolve(bytes, bytes[], string[])` signature
    function resolve(bytes calldata name, bytes[] memory data, string[] memory gateways)
        external
        view
        override(IUniversalResolverV1)
        returns (Result[] memory, address)
    {
        // Note: This will likely revert if the implementation is V2
         ccipRead(
            _getImplementation(),
            abi.encodeWithSelector(bytes4(keccak256("resolve(bytes,bytes[],string[])")), name, data, gateways)
         );
    }

    // V2 `reverse(bytes, uint256)` signature
    function reverse(bytes calldata lookupAddress, uint256 coinType)
        external
        view
        override(IUniversalResolverV2)
        returns (string memory, address, address)
    {
        // Note: This will likely revert if the implementation is V1
         ccipRead(
            _getImplementation(),
            abi.encodeWithSelector(IUniversalResolverV2.reverse.selector, lookupAddress, coinType)
         );
    }

    // V1 `reverse(bytes)` signature
    function reverse(bytes calldata reverseName)
        external
        view
        override(IUniversalResolverV1)
        returns (string memory, address, address, address)
    {
        ccipRead(
            _getImplementation(),
            abi.encodeWithSelector(bytes4(keccak256("reverse(bytes)")), reverseName)
        );
    }

    // V1 `reverse(bytes, string[])` signature
    function reverse(bytes calldata reverseName, string[] memory gateways)
        external
        view
        override(IUniversalResolverV1)
        returns (string memory, address, address, address)
    {
        // Note: This will likely revert if the implementation is V2
        ccipRead(
            _getImplementation(),
            abi.encodeWithSelector(bytes4(keccak256("reverse(bytes,string[])")), reverseName, gateways)
        );
    }

    // --- Callbacks (Must be implemented on the proxy itself) ---
    // These are targets for the CCIP-Read process and must also call the implementation, potentially triggering further lookups.

    // V1 `resolveCallback`
    function resolveCallback(bytes calldata response, bytes calldata extraData)
        external
        view
        override(IUniversalResolverV1)
        returns (Result[] memory, address)
    {
         ccipRead(
            _getImplementation(),
            abi.encodeWithSelector(IUniversalResolverV1.resolveCallback.selector, response, extraData)
         );
    }

    // V1 `resolveSingleCallback`
    function resolveSingleCallback(bytes calldata response, bytes calldata extraData)
        external
        view
        override(IUniversalResolverV1)
        returns (bytes memory, address)
    {
        ccipRead(
            _getImplementation(),
            abi.encodeWithSelector(IUniversalResolverV1.resolveSingleCallback.selector, response, extraData)
        );
    }

    // V1 `reverseCallback`
    function reverseCallback(bytes calldata response, bytes calldata extraData)
        external
        view
        override(IUniversalResolverV1)
        returns (string memory, address, address, address)
    {
        ccipRead(
            _getImplementation(),
            abi.encodeWithSelector(IUniversalResolverV1.reverseCallback.selector, response, extraData)
        );
    }

    // V2 `resolveCallback`
    function resolveCallback(
        UniversalResolverV2.ResolverInfo calldata info,
        UniversalResolverV2.Lookup[] calldata lookups,
        bytes calldata extraData
    ) external view returns (bytes memory, address) {
        // Explicit selector recommended due to structs from implementation
        bytes4 selector = bytes4(keccak256("resolveCallback((bytes,uint256,bytes32,address,bool),(address,uint32,bytes,bytes,bytes)[],bytes)"));
        ccipRead(_getImplementation(), abi.encodeWithSelector(selector, info, lookups, extraData));
    }


    // V2 `reverseNameCallback`
    function reverseNameCallback(
        UniversalResolverV2.ResolverInfo calldata infoRev,
        UniversalResolverV2.Lookup[] calldata lookups,
        bytes memory extraData
    ) external view returns (string memory, address, address) {
        bytes4 selector = bytes4(keccak256("reverseNameCallback((bytes,uint256,bytes32,address,bool),(address,uint32,bytes,bytes,bytes)[],bytes)"));
        ccipRead(
            _getImplementation(),abi.encodeWithSelector(selector, infoRev, lookups, extraData)
        );
    }

    // V2 `reverseAddressCallback`
    function reverseAddressCallback(
        UniversalResolverV2.ResolverInfo calldata info,
        UniversalResolverV2.Lookup[] calldata lookups,
        bytes calldata extraData
    ) external view returns (string memory, address, address) {
        bytes4 selector = bytes4(keccak256("reverseAddressCallback((bytes,uint256,bytes32,address,bool),(address,uint32,bytes,bytes,bytes)[],bytes)"));
        ccipRead(
            _getImplementation(),abi.encodeWithSelector(selector, info, lookups, extraData)
        );
    }

    // --- Other Methods ---

    /**
     * @dev Implements supportsInterface - forwards to implementation
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        // Direct forwarding without CCIP-Read handling
        return IERC165(_getImplementation()).supportsInterface(interfaceId);
    }

    function findResolver(bytes calldata name) external view returns (address, bytes32, uint256) {
        // This method doesn't use CCIP-Read, so direct forwarding is fine
        return IUniversalResolverV1(_getImplementation()).findResolver(name);
    }

    // --- Fallback and Receive ---

    /**
     * @dev Fallback function reverts, as forwarding via delegatecall is disallowed
     * and all supported functions must be explicitly defined.
     */
    fallback() external payable {
        revert FunctionNotSupported();
    }

    /**
     * @dev Receive function for plain Ether transfers
     */
    receive() external payable {}
}