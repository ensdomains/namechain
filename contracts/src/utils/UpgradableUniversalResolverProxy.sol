// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/utils/StorageSlot.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

// UR Imports
import {UniversalResolver as UniversalResolverV1} from "ens-contracts/universalResolver/UniversalResolver.sol";

// CCIP-Read Imports
import {EIP3668, OffchainLookup} from "ens-contracts/ccipRead/EIP3668.sol";
import {BytesUtils} from "ens-contracts/utils/BytesUtils.sol";

/**
 * @title UpgradableUniversalResolverProxy
 * @dev A specialized proxy for UniversalResolver that forwards method calls
 * and properly handles CCIP-Read reverts. Admin can upgrade the implementation.
 */
contract UpgradableUniversalResolverProxy {
    // Storage slot for implementation address (EIP-1967 compatible)
    bytes32 private constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // Storage slot for admin (EIP-1967 compatible)
    bytes32 private constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    // Custom errors
    error CallerNotAdmin();
    error InvalidImplementation();
    error SameImplementation();

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
        // Check if implementation supports the UniversalResolver interface
        // try IERC165(newImplementation).supportsInterface(type(IUniversalResolver).interfaceId) returns (bool supported) {
        //     if (!supported) {
        //         revert InvalidImplementation();
        //     }
        // } catch {
        //     revert InvalidImplementation();
        // }
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

    // --- Fallback and Receive ---

    /**
     * @dev Fallback function that handles forwarding calls to the implementation
     * and properly manages CCIP-Read reverts.
     */
    fallback() external {
        (bool ok, bytes memory v) = _getImplementation().staticcall(msg.data);
        if (!ok && bytes4(v) == OffchainLookup.selector) {
            EIP3668.Params memory p = EIP3668.decode(BytesUtils.substring(v, 4, v.length - 4));
            if (p.sender == _getImplementation()) {
                revert OffchainLookup(address(this), p.urls, p.callData, p.callbackFunction, p.extraData);
            }
        }

        if (ok) {
            assembly {
                return(add(v, 32), mload(v))
            }
        } else {
            assembly {
                revert(add(v, 32), mload(v))
            }
        }
    }
}
