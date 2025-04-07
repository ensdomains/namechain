
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {MockBridgeHelper} from "./MockBridgeHelper.sol";
import {MockL2Bridge} from "./MockL2Bridge.sol";
import {IController} from "./IController.sol";

// L2 Registry interface
interface IMockL2Registry {
    function register(
        string calldata name,
        address owner,
        address subregistry,
        address resolver,
        uint96 flags,
        uint64 expires
    ) external returns (uint256 tokenId);
    
    function setOwner(uint256 tokenId, address newOwner) external;
}

interface IMockL2Bridge {
    function sendMessageToL1(bytes calldata message) external;
}

/**
 * @title MockL2MigrationController
 * @dev Example contract that processes messages for L2 ENS operations
 */
contract MockL2MigrationController is IController {
    IMockL2Registry public registry;
    address public bridgeHelper;
    IMockL2Bridge public bridge;
    
    // Events for tracking actions
    event NameRegisteredOnL2(string name, address owner, address subregistry);
    event NameEjectedOnL2(string name, uint256 tokenId);
    
    constructor(address _registry, address _helper, address _bridge) {
        registry = IMockL2Registry(_registry);
        bridgeHelper = _helper;
        bridge = IMockL2Bridge(_bridge);
    }
    
    /**
     * @dev Process a message received from the bridge
     */
    function processMessage(bytes calldata message) external override {
        require(msg.sender == address(bridge), "Not authorized");
        
        bytes4 messageType = bytes4(message[:4]);
        
        if (messageType == bytes4(keccak256("NAME_MIGRATION"))) {
            (string memory name, address owner, address subregistry) =
                MockBridgeHelper(bridgeHelper).decodeMigrationMessage(message);
                
            // Default values for remaining parameters
            address resolver = address(0);
            uint96 flags = 0;
            uint64 expires = uint64(block.timestamp + 365 days);
            
            registry.register(name, owner, subregistry, resolver, flags, expires);
            emit NameRegisteredOnL2(name, owner, subregistry);
        }
        else if (messageType == bytes4(keccak256("NAME_EJECTION"))) {
            (string memory name, , , ) = MockBridgeHelper(bridgeHelper).decodeEjectionMessage(message);
            
            uint256 tokenId = uint256(keccak256(abi.encodePacked(name)));
            
            // This simulates the name being locked on L2 once it has been moved to L1
            registry.setOwner(tokenId, address(this));
            
            emit NameEjectedOnL2(name, tokenId);
        }
    }
    
    /**
     * @dev Request ejection of a name from L2 to L1
     */
    function requestEjection(string calldata name, address l1Owner, address l1Subregistry, uint64 expiry) external {
        uint256 tokenId = uint256(keccak256(abi.encodePacked(name)));

        registry.setOwner(tokenId, address(this));
        
        bytes memory message = MockBridgeHelper(bridgeHelper).encodeEjectionMessage(
            name,
            l1Owner,
            l1Subregistry,
            expiry
        );
        
        bridge.sendMessageToL1(message);
    }
}
