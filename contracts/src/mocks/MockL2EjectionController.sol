// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {IBridge} from "./IBridge.sol";
import {MockBridgeHelper} from "./MockBridgeHelper.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {IRegistry} from "../common/IRegistry.sol";
import {IL2EjectionController} from "../L2/IL2EjectionController.sol";

/**
 * @title MockL2EjectionController
 * @dev Implementation of IL2EjectionController for L2 ENS operations
 */
contract MockL2EjectionController is IL2EjectionController {
    IPermissionedRegistry public registry;
    address public bridgeHelper;
    IBridge public bridge;
    
    // Events for tracking actions
    event NameMigrated(uint256 labelHash, address owner, address subregistry);
    event NameEjected(uint256 tokenId, address l1Owner, address l1Subregistry, uint64 expires);
    
    constructor(address _registry, address _helper, address _bridge) {
        registry = IPermissionedRegistry(_registry);
        bridgeHelper = _helper;
        bridge = IBridge(_bridge);
    }
    
    /**
     * @dev Implements IL2EjectionController.ejectToL1
     * Called when a user wants to eject a name from L2 to L1
     */
    function ejectToL1(
        uint256 tokenId,
        address l1Owner,
        address l1Subregistry,
        uint32 flags,
        uint64 expires,
        bytes memory data
    ) public override {
        // Get the name directly from the parameters
        string memory name = abi.decode(data, (string));
        
        // Encode ejection message
        bytes memory message = MockBridgeHelper(bridgeHelper).encodeEjectionMessage(
            name,
            l1Owner,
            l1Subregistry,
            expires
        );
        
        // Send the message to L1
        bridge.sendMessageToL1(message);
        
        emit NameEjected(tokenId, l1Owner, l1Subregistry, expires);
    }
    
    /**
     * @dev Implements IL2EjectionController.completeMigration
     */
    function completeMigration(
        uint256 labelHash,
        address l2Owner,
        address l2Subregistry,
        bytes memory data
    ) external override {
        // // Extract name from data
        string memory name = abi.decode(data, (string));
        console.log("ens name:");
        console.log(name);
        
        // // Require the name to be valid
        require(bytes(name).length > 0, "Name not found for labelHash");
        
        // // Default values for registration
        address resolver = address(0);
        uint96 flags = 0; // Using uint96 flags for ETHRegistry
        uint64 expires = uint64(block.timestamp + 365 days);
        
        // // Register the name on L2
        // registry.register(name, l2Owner, IRegistry(l2Subregistry), resolver, flags, expires);
        
        emit NameMigrated(labelHash, l2Owner, l2Subregistry);
    }
    
    /**
     * @dev Utility function to request ejection of a name with a simplified interface
     */
    function requestEjection(string calldata name, address l1Owner, address l1Subregistry, uint64 expiry) external {
        // Calculate tokenId from name
        uint256 tokenId = uint256(keccak256(bytes(name)));
        
        // Encode ejection message
        bytes memory message = MockBridgeHelper(bridgeHelper).encodeEjectionMessage(
            name,
            l1Owner,
            l1Subregistry,
            expiry
        );
        
        // Send the message to L1
        bridge.sendMessageToL1(message);
        
        emit NameEjected(tokenId, l1Owner, l1Subregistry, expiry);
    }
}