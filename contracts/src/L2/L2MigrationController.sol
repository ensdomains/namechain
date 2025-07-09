// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import {TransferData, MigrationData} from "../common/TransferData.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRegistry} from "../common/IRegistry.sol";
import {IRegistryDatastore} from "../common/IRegistryDatastore.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";
import {NameUtils} from "../common/NameUtils.sol";
import {PermissionedRegistry} from "../common/PermissionedRegistry.sol";
import {SimpleRegistryMetadata} from "../common/SimpleRegistryMetadata.sol";

/**
 * @title L2MigrationController
 * @dev Controller that handles migration messages from L1 to L2
 */
contract L2MigrationController is Ownable {
    error UnauthorizedCaller(address caller);
    error MigrationFailed();
    error InvalidTLD(bytes32 labelHash);
    error NameAlreadyRegistered(bytes dnsEncodedName);
    error LabelNotFound(bytes dnsEncodedName, string label);

    // Events
    event MigrationCompleted(bytes dnsEncodedName, uint256 newTokenId);

    bytes32 public constant ETH_TLD_HASH = keccak256(bytes("eth"));

    address public immutable bridge;
    address public immutable ejectionController;
    PermissionedRegistry public immutable ethRegistry;
    IRegistryDatastore public immutable datastore;

    modifier onlyBridge() {
        if (msg.sender != bridge) {
            revert UnauthorizedCaller(msg.sender);
        }
        _;
    }

    constructor(
        address _bridge, 
        address _ejectionController,
        PermissionedRegistry _ethRegistry, 
        IRegistryDatastore _datastore
    ) Ownable(msg.sender) {
        bridge = _bridge;
        ejectionController = _ejectionController;
        ethRegistry = _ethRegistry;
        datastore = _datastore;
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
        // Find the registry and validate the registry tree
        (PermissionedRegistry registry, string memory label, bool exists) = _findAndValidateLabelStructure(dnsEncodedName, 0);

        if (exists) {
            revert NameAlreadyRegistered(dnsEncodedName);
        }

        // register the name
        uint256 tokenId = registry.register(
            label,
            /*
            * If the migrated name is being kept on L1 then we need to 
            * mint it to the ejection controller so that the user can eject it 
            * back to L2 in future.
            *
            * The ejection controller won't trigger ejection bridge calls for names 
            * that are minted to it.
            */
            migrationData.toL1 ? ejectionController : migrationData.transferData.owner,
            new PermissionedRegistry(
               datastore,
                new SimpleRegistryMetadata(),
                registry.ALL_ROLES()
            ),
            migrationData.transferData.resolver,
            migrationData.transferData.roleBitmap,
            migrationData.transferData.expires
        );

        // if the migrated name is being kept on L1 then we need to transfer it to the ejection controller
        // but without triggering ejection

        emit MigrationCompleted(dnsEncodedName, tokenId);
    }

    /**
     * @dev Recursively finds and validates the label registry structure
     * @param name The DNS-encoded name
     * @param offset The current offset in the name
     * @return registry The registry at this level
     * @return label The label at this level
     * @return exists True if the label at this level exists (only relevant for leftmost label)
     */
    function _findAndValidateLabelStructure(
        bytes memory name,
        uint256 offset
    ) internal view returns (PermissionedRegistry registry, string memory label, bool exists) {
        uint256 size = uint8(name[offset]);
        
        // If we reach the end (size == 0), we should be at the root
        if (size == 0) {
            return (PermissionedRegistry(address(0)), "", true);
        }
        
        // Check if this is the leftmost label (offset == 0)
        bool isLeftmostLabel = (offset == 0);
        
        // Recursively process the next part of the name (moving right to left)
        (PermissionedRegistry parentRegistry,, ) = _findAndValidateLabelStructure(
            name,
            offset + 1 + size
        );
        
        // Read the current label
        (bytes32 labelHash, ) = NameCoder.readLabel(name, offset);
        
        // If we're at the rightmost position (parentRegistry is zero), this should be "eth"
        if (address(parentRegistry) == address(0)) {
            if (labelHash != ETH_TLD_HASH) {
                revert InvalidTLD(labelHash);
            }
            // Return the .eth registry
            return (ethRegistry, "", true);
        }
        
        label = NameUtils.readLabel(name, offset);

        // For non-TLD labels, check if they exist in the parent registry
        bool labelExists = address(parentRegistry.getSubregistry(label)) != address(0);
        
        // If this is the leftmost label (the one being migrated), return the result
        if (isLeftmostLabel) {
            if (labelExists) {
                return (parentRegistry, label, true);
            } else {
                return (parentRegistry, label, false);
            }
        }
        
        // For all other labels, they must exist
        if (!labelExists) {
            revert LabelNotFound(name, label);
        }
        
        return (parentRegistry, label, true);
    }
} 