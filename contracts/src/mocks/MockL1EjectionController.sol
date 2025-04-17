// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IBridge} from "./IBridge.sol";
import {MockBridgeHelper} from "./MockBridgeHelper.sol";
import {IRegistry} from "../common/IRegistry.sol";
import {L1ETHRegistry} from "../L1/L1ETHRegistry.sol";
import {IL1EjectionController} from "../L1/IL1EjectionController.sol";

/**
 * @title MockL1EjectionController
 * @dev Implementation of IL1EjectionController for L1 ENS operations
 */
contract MockL1EjectionController is IL1EjectionController {
    L1ETHRegistry public registry;
    address public bridgeHelper;
    IBridge public bridge;
    
    // Events for tracking actions
    event NameEjected(uint256 labelHash, address owner, address subregistry, uint64 expires);
    event NameMigrated(uint256 tokenId, address l2Owner, address l2Subregistry);
    event RenewalSynced(uint256 tokenId, uint64 newExpiry);
    
    constructor(address _registry, address _helper, address _bridge) {
        registry = L1ETHRegistry(_registry);
        bridgeHelper = _helper;
        bridge = IBridge(_bridge);
    }
    
    /**
     * @dev Implements IL1EjectionController.migrateToNamechain
     */
    function migrateToNamechain(
        uint256 tokenId, 
        address l2Owner, 
        address l2Subregistry, 
        bytes memory data
    ) external override {
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
     * @dev Implements IL1EjectionController.completeEjection
     */
    function completeEjection(
        uint256 labelHash,
        address l1Owner,
        address l1Subregistry,
        uint32 flags,
        uint64 expires,
        bytes memory data
    ) external override {
        // Process the ejection by calling the L1ETHRegistry
        uint256 tokenId = registry.ejectFromNamechain(
            labelHash,
            l1Owner,
            IRegistry(l1Subregistry),
            expires
        );
        
        emit NameEjected(labelHash, l1Owner, l1Subregistry, expires);
    }
    
    /**
     * @dev Implements IL1EjectionController.syncRenewalFromL2
     */
    function syncRenewalFromL2(uint256 tokenId, uint64 newExpiry) external override {
        // Update expiration on L1
        registry.updateExpiration(tokenId, newExpiry);
        
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