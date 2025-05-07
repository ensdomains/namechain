// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IBridge} from "./IBridge.sol";
import {MockBridgeHelper} from "./MockBridgeHelper.sol";
import {IRegistry} from "../common/IRegistry.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";

/**
 * @title MockL1EjectionController
 * @dev Controller for handling L1 ENS operations with PermissionedRegistry
 */
contract MockL1EjectionController {
    IPermissionedRegistry public registry;
    address public bridgeHelper;
    IBridge public bridge;
    
    // Events for tracking actions
    event NameEjected(uint256 labelHash, address owner, address subregistry, uint64 expires);
    event NameMigrated(uint256 tokenId, address l2Owner, address l2Subregistry);
    event RenewalSynced(uint256 tokenId, uint64 newExpiry);
    
    constructor(address _registry, address _helper, address _bridge) {
        registry = IPermissionedRegistry(_registry);
        bridgeHelper = _helper;
        bridge = IBridge(_bridge);
    }
    
    /**
     * @dev Handles migration to the L2 namechain
     */
    function migrateToNamechain(
        uint256 tokenId, 
        address l2Owner, 
        address l2Subregistry, 
        bytes memory data
    ) external {
        // Get the name directly from the parameters
        string memory name = abi.decode(data, (string));
        
        // Create and send migration message
        bytes memory message = MockBridgeHelper(bridgeHelper).encodeMigrationMessage(
            name,
            l2Owner,
            l2Subregistry
        );
        
        // Send migration message to L2
        bridge.sendMessageToL2(message);
        
        emit NameMigrated(tokenId, l2Owner, l2Subregistry);
    }
    
    /**
     * @dev Handles completion of ejection from L2
     */
    function completeEjection(
        uint256 labelHash,
        address l1Owner,
        address l1Subregistry,
        uint32 flags,
        uint64 expires,
        bytes memory data
    ) external {
        string memory label = "";
        label = abi.decode(data, (string));
        
        // Register the name with the PermissionedRegistry
        uint256 rolesBitmap = 0xF; // Basic roles for testing
        uint256 tokenId = registry.register(
            label,
            l1Owner,
            IRegistry(l1Subregistry),
            address(0), // resolver
            rolesBitmap,
            expires
        );
        
        emit NameEjected(labelHash, l1Owner, l1Subregistry, expires);
    }
    
    /**
     * @dev Handles synchronization of renewals from L2
     */
    function syncRenewalFromL2(uint256 tokenId, uint64 newExpiry) external {
        // Update expiration using the PermissionedRegistry
        registry.renew(tokenId, newExpiry);
        
        emit RenewalSynced(tokenId, newExpiry);
    }
    
    /**
     * @dev Utility function to request migration of a name with a simplified interface
     * This method is used by the test scripts
     */
    function requestMigration(string calldata name, address l2Owner, address l2Subregistry) external {
        // Calculate tokenId from name
        uint256 tokenId = uint256(keccak256(abi.encodePacked(name)));
        
        // Create and send migration message
        bytes memory message = MockBridgeHelper(bridgeHelper).encodeMigrationMessage(
            name,
            l2Owner,
            l2Subregistry
        );
        
        // Send migration message to L2
        bridge.sendMessageToL2(message);
        
        emit NameMigrated(tokenId, l2Owner, l2Subregistry);
    }
}
