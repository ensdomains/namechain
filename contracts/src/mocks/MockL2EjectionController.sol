// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IBridge} from "./IBridge.sol";
import {MockBridgeHelper} from "./MockBridgeHelper.sol";
import {IPermissionedRegistry} from "../common/IPermissionedRegistry.sol";
import {IRegistry} from "../common/IRegistry.sol";

/**
 * @title MockL2EjectionController
 * @dev Controller for handling L2 ENS operations with PermissionedRegistry
 */
contract MockL2EjectionController {
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
     * @dev Handles ejection to L1
     */
    function ejectToL1(
        uint256 tokenId,
        address l1Owner,
        address l1Subregistry,
        uint32 flags,
        uint64 expires,
        bytes memory data
    ) public {
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
     * @dev Handles completion of migration from L1
     */
    function completeMigration(
        uint256 labelHash,
        address l2Owner,
        address l2Subregistry,
        bytes memory data
    ) external {
        // Extract name from data
        string memory name = abi.decode(data, (string));
        // Require the name to be valid
        require(bytes(name).length > 0, "Name not found for labelHash");
        
        // Default values for registration
        address resolver = address(0);
        uint256 roleBitmap = 0xF; // Basic role bitmap for testing
        uint64 expires = uint64(block.timestamp + 365 days);
        
        // Register the name on L2 using PermissionedRegistry
        registry.register(name, l2Owner, IRegistry(l2Subregistry), resolver, roleBitmap, expires);
        
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
