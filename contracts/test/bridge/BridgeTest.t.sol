// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../src/mocks/MockL1Bridge.sol";
import "../../src/mocks/MockL2Bridge.sol";
import "../../src/mocks/MockBridgeHelper.sol";
import "../../src/mocks/MockL1MigrationController.sol";
import "../../src/mocks/MockL2MigrationController.sol";

// Mock registry implementations
contract MockL1Registry is IMockL1Registry {
    event NameRegistered(string name, address owner, address subregistry, uint64 expiry);
    event NameBurned(uint256 tokenId);
    
    mapping(uint256 => bool) public registered;
    
    function registerEjectedName(
        string calldata name,
        address owner,
        address subregistry,
        uint64 expiry
    ) external override returns (uint256 tokenId) {
        tokenId = uint256(keccak256(abi.encodePacked(name)));
        registered[tokenId] = true;
        emit NameRegistered(name, owner, subregistry, expiry);
        return tokenId;
    }
    
    function burnName(uint256 tokenId) external override {
        registered[tokenId] = false;
        emit NameBurned(tokenId);
    }
}

contract MockL2Registry is IMockL2Registry {
    event NameRegistered(string name, address owner, address subregistry);
    event OwnerChanged(uint256 tokenId, address newOwner);
    
    mapping(uint256 => address) public owners;
    
    function register(
        string calldata name,
        address owner,
        address subregistry,
        address /* resolver */,
        uint96 /* flags */,
        uint64 /* expires */
    ) external override returns (uint256 tokenId) {
        tokenId = uint256(keccak256(abi.encodePacked(name)));
        owners[tokenId] = owner;
        emit NameRegistered(name, owner, subregistry);
        return tokenId;
    }
    
    function setOwner(uint256 tokenId, address newOwner) external override {
        owners[tokenId] = newOwner;
        emit OwnerChanged(tokenId, newOwner);
    }
}

contract BridgeTest is Test {
    // Components for the test
    MockL1Registry l1Registry;
    MockL2Registry l2Registry;
    MockL1Bridge l1Bridge;
    MockL2Bridge l2Bridge;
    MockBridgeHelper bridgeHelper;
    MockL1MigrationController l1Controller;
    MockL2MigrationController l2Controller;
    
    // Test accounts
    address user1 = address(0x1);
    address user2 = address(0x2);
    
    function setUp() public {
        // Deploy the contracts
        l1Registry = new MockL1Registry();
        l2Registry = new MockL2Registry();
        
        bridgeHelper = new MockBridgeHelper();
        
        l1Bridge = new MockL1Bridge(address(0));
        l2Bridge = new MockL2Bridge(address(0));
        
        l1Controller = new MockL1MigrationController(address(l1Registry), address(bridgeHelper), address(l1Bridge));
        l2Controller = new MockL2MigrationController(address(l2Registry), address(bridgeHelper), address(l2Bridge));
        
        // Set the controller contracts as targets for the bridges
        l1Bridge.setTargetContract(address(l1Controller));
        l2Bridge.setTargetContract(address(l2Controller));
    }
    
    function testNameMigrationFromL1ToL2() public {
        string memory name = "examplename.eth";
        address l2Owner = user2;
        address l2Subregistry = address(0x123);
        
        // Step 1: Initiate migration on L1
        vm.startPrank(user1);
        l1Controller.requestMigration(name, l2Owner, l2Subregistry);
        vm.stopPrank();
        
        // Step 2: In a real scenario, a relayer would observe the L1 event and call L2
        // For testing, we simulate this by directly calling the L2 bridge
        bytes memory message = bridgeHelper.encodeMigrationMessage(name, l2Owner, l2Subregistry);
        
        vm.expectEmit(true, true, true, true);
        emit MockL2Registry.NameRegistered(name, l2Owner, l2Subregistry);
        
        l2Bridge.receiveMessageFromL1(message);
        
        // Verify owner is set correctly on L2
        uint256 tokenId = uint256(keccak256(abi.encodePacked(name)));
        assertEq(l2Registry.owners(tokenId), l2Owner);
    }
    
    function testNameEjectionFromL2ToL1() public {
        string memory name = "premiumname.eth";
        address l1Owner = user1;
        address l1Subregistry = address(0x456);
        uint64 expiry = uint64(block.timestamp + 365 days);
        
        // Step 1: Initiate ejection on L2
        vm.startPrank(user2);
        l2Controller.requestEjection(name, l1Owner, l1Subregistry, expiry);
        vm.stopPrank();
        
        // Step 2: Simulate the relayer by directly calling the L1 bridge
        bytes memory message = bridgeHelper.encodeEjectionMessage(name, l1Owner, l1Subregistry, expiry);
        
        vm.expectEmit(true, true, true, true);
        emit MockL1Registry.NameRegistered(name, l1Owner, l1Subregistry, expiry);
        
        l1Bridge.receiveMessageFromL2(message);
        
        // Verify the name is registered on L1
        uint256 tokenId = uint256(keccak256(abi.encodePacked(name)));
        assertTrue(l1Registry.registered(tokenId));
    }
    
    function testCompleteRoundTrip() public {
        // Test a complete cycle: L1 -> L2 -> L1
        string memory name = "roundtrip.eth";
        
        // Step 1: Migrate from L1 to L2
        vm.startPrank(user1);
        l1Controller.requestMigration(name, user2, address(0x123));
        vm.stopPrank();
        
        // Simulate the relayer for L1->L2
        bytes memory migrationMsg = bridgeHelper.encodeMigrationMessage(name, user2, address(0x123));
        l2Bridge.receiveMessageFromL1(migrationMsg);
        
        // Step 2: Now eject from L2 back to L1
        vm.startPrank(user2);
        l2Controller.requestEjection(name, user1, address(0x456), uint64(block.timestamp + 365 days));
        vm.stopPrank();
        
        // Simulate the relayer for L2->L1
        bytes memory ejectionMsg = bridgeHelper.encodeEjectionMessage(
            name, 
            user1, 
            address(0x456), 
            uint64(block.timestamp + 365 days)
        );
        l1Bridge.receiveMessageFromL2(ejectionMsg);
        
        // Verify the results
        uint256 tokenId = uint256(keccak256(abi.encodePacked(name)));
        assertTrue(l1Registry.registered(tokenId));
        assertEq(l2Registry.owners(tokenId), address(l2Controller)); // Bridge should own it on L2 now
    }
}
