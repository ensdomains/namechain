// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {TransferData, MigrationData} from "../common/TransferData.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRegistry} from "../common/IRegistry.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {NameUtils} from "../common/NameUtils.sol";

/**
 * @title L2MigrationController
 * @dev Controller that handles migration messages from L1 to L2
 */
contract L2MigrationController is Ownable {
    error UnauthorizedCaller(address caller);
    error MigrationFailed();
    error InvalidTLD(bytes32 labelHash);
    error NameAlreadyRegistered(string label);
    error LabelNotFound(string label);

    // Events
    event MigrationCompleted(bytes dnsEncodedName, MigrationData migrationData);

    uint256 public constant ETH_TLD_HASH = keccak256(bytes("eth"));

    address public immutable bridge;
    /**
     * @dev The .eth registry
     */
    IRegistry public immutable permissionedregistry;

    modifier onlyBridge() {
        if (msg.sender != bridge) {
            revert UnauthorizedCaller(msg.sender);
        }
        _;
    }

    constructor(address _bridge, IRegistry _permissionedregistry) Ownable(msg.sender) {
        bridge = _bridge;
        permissionedregistry = _permissionedregistry;
    }

    /**
     * @dev Complete migration from L1 to L2
     * Called by the bridge when a migration message is received from L1
     * 
     * @param dnsEncodedName The DNS encoded name being migrated
     * @param migrationData The migration data containing transfer details
     */
    function completeMigrationFromL1(
        bytes memory dnsEncodedName,
        MigrationData memory migrationData
    ) external onlyBridge {
        // Validate that this is a .eth 2LD name and traverse the registry tree
        _validateAndTraverseRegistry(dnsEncodedName);
        
        emit MigrationCompleted(dnsEncodedName, migrationData);
    }

    /**
     * @dev Validates the DNS encoded name is a .eth 2LD and traverses the registry tree
     * Similar to UniversalResolver._findResolver but validates each step exists
     */
    function _validateAndTraverseRegistry(bytes memory dnsEncodedName) internal view {
        // Find the .eth registry and validate the registry tree
        _findAndValidateRegistry(dnsEncodedName, 0);
    }

    /**
     * @dev Recursively finds and validates the registry structure
     * @param name The DNS-encoded name
     * @param offset The current offset in the name
     * @return registry The registry at this level
     * @return exact True if we found an exact match
     */
    function _findAndValidateRegistry(
        bytes memory name,
        uint256 offset
    ) internal view returns (IRegistry registry, bool exact) {
        uint256 size = uint8(name[offset]);
        
        // If we reach the end (size == 0), we should be at the root
        if (size == 0) {
            // This should never happen for a .eth 2LD, but handle gracefully
            return (IRegistry(address(0)), true);
        }
        
        // Recursively process the next part of the name (moving right to left)
        (IRegistry parentRegistry, bool parentExact) = _findAndValidateRegistry(
            name,
            offset + 1 + size
        );
        
        // Read the current label hash
        (bytes32 labelHash, ) = NameCoder.readLabel(name, offset);
        
        // If we're at the rightmost position (parentRegistry is zero), this should be "eth"
        if (address(parentRegistry) == address(0)) {
            if (labelHash != ETH_TLD_HASH) {
                revert InvalidTLD(labelHash);
            }
            // Return the .eth registry
            return (permissionedregistry, true);
        }
        
        // For non-TLD labels, check if they exist in the parent registry
        if (parentExact) {
            // We need the label string to call getSubregistry, so read it with NameUtils
            string memory label = NameUtils.readLabel(name, offset);
            // Check if this label is registered in the parent registry
            IRegistry subregistry = parentRegistry.getSubregistry(label);
            if (address(subregistry) == address(0)) {
                revert LabelNotFound(label);
            }
            return (subregistry, true);
        } else {
            // Parent registry doesn't exist exactly, so this path is invalid
            string memory label = NameUtils.readLabel(name, offset);
            revert LabelNotFound(label);
        }
    }
} 