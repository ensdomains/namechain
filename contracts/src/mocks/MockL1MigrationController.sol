// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {MockBridgeHelper} from "./MockBridgeHelper.sol";
import {MockL1Bridge} from "./MockL1Bridge.sol";
import {IController} from "./IController.sol";

// L1 Registry interface
interface IMockL1Registry {
    function registerEjectedName(
        string calldata name,
        address owner,
        address subregistry,
        uint64 expiry
    ) external returns (uint256 tokenId);
    
    function burnName(uint256 tokenId) external;
}

interface IMockL1Bridge {
    function sendMessageToL2(bytes calldata message) external;
}

/**
 * @title MockL1MigrationController
 * @dev Example contract that processes messages for L1 ENS operations
 */
contract MockL1MigrationController is IController {
    IMockL1Registry public registry;
    address public bridgeHelper;
    IMockL1Bridge public bridge;
    
    // Events for tracking actions
    event NameRegisteredOnL1(string name, address owner, address subregistry, uint64 expiry);
    event NameBurnedOnL1(string name, uint256 tokenId);
    
    constructor(address _registry, address _helper, address _bridge) {
        registry = IMockL1Registry(_registry);
        bridgeHelper = _helper;
        bridge = IMockL1Bridge(_bridge);
    }
    
    /**
     * @dev Process a message received from the bridge
     */
    function processMessage(bytes calldata message) external override {
        require(msg.sender == address(bridge), "Not authorized");
        
        bytes4 messageType = abi.decode(message, (bytes4));
        
        if (messageType == bytes4(keccak256("NAME_EJECTION"))) {
            (string memory name, address owner, address subregistry, uint64 expiry) =
                MockBridgeHelper(bridgeHelper).decodeEjectionMessage(message);
                
            registry.registerEjectedName(name, owner, subregistry, expiry);
            emit NameRegisteredOnL1(name, owner, subregistry, expiry);
        }
        else if (messageType == bytes4(keccak256("NAME_MIGRATION"))) {
            (string memory name, , ) = MockBridgeHelper(bridgeHelper).decodeMigrationMessage(message);
            
            // In a real implementation, we'd calculate the token ID correctly
            uint256 tokenId = uint256(keccak256(abi.encodePacked(name)));
            registry.burnName(tokenId);
            emit NameBurnedOnL1(name, tokenId);
        }
    }
    
    /**
     * @dev Request migration of a name from L1 to L2
     */
    function requestMigration(string calldata name, address l2Owner, address l2Subregistry) external {
        bytes memory message = MockBridgeHelper(bridgeHelper).encodeMigrationMessage(
            name, 
            l2Owner, 
            l2Subregistry
        );
        
        bridge.sendMessageToL2(message);
    }
}
