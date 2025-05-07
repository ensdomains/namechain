// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../src/mocks/MockL1Bridge.sol";
import "../../src/mocks/MockL2Bridge.sol";
import "../../src/mocks/MockBridgeHelper.sol";
import "../../src/mocks/MockL1EjectionController.sol";
import "../../src/mocks/MockL2EjectionController.sol";

import { IRegistry } from "../../src/common/IRegistry.sol";
import { IPermissionedRegistry } from "../../src/common/IPermissionedRegistry.sol";
import { ITokenObserver } from "../../src/common/ITokenObserver.sol";

// Simple mock implementation
contract SimpleMockRegistry {
    event NewSubname(uint256 indexed labelHash, string label);
    event NameRelinquished(uint256 indexed tokenId, address relinquishedBy);
    event NameRenewed(uint256 indexed tokenId, uint64 newExpiration, address renewedBy);
    event TokenObserverSet(uint256 indexed tokenId, address observer);
    
    mapping(uint256 => bool) public registered;
    mapping(uint256 => address) public owners;
    mapping(uint256 => IRegistry) public subregistries;
    mapping(uint256 => address) public resolvers;
    mapping(uint256 => uint64) public expirations;
    mapping(uint256 => ITokenObserver) public tokenObservers;
    
    bytes32 public constant ROOT_RESOURCE = bytes32(0);
    
    // Role definitions for testing
    uint256 public constant ROLE_REGISTRAR = 1 << 0;
    uint256 public constant ROLE_RENEW = 1 << 1;
    uint256 public constant ROLE_SET_SUBREGISTRY = 1 << 2;
    uint256 public constant ROLE_SET_RESOLVER = 1 << 3;
    uint256 public constant ROLE_SET_TOKEN_OBSERVER = 1 << 4;
    
    mapping(bytes32 => mapping(address => uint256)) public roles;
    
    constructor() {
        // Grant all roles to the deployer for testing
        roles[ROOT_RESOURCE][msg.sender] = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    }
    
    function register(
        string calldata label,
        address owner,
        IRegistry subregistry,
        address resolver,
        uint256 roleBitmap,
        uint64 expires
    ) external returns (uint256 tokenId) {
        require(roles[ROOT_RESOURCE][msg.sender] & ROLE_REGISTRAR != 0, "Not authorized");
        tokenId = uint256(keccak256(abi.encodePacked(label)));
        
        registered[tokenId] = true;
        owners[tokenId] = owner;
        subregistries[tokenId] = subregistry;
        resolvers[tokenId] = resolver;
        expirations[tokenId] = expires;
        
        // Grant roles to the owner
        bytes32 resource = bytes32(tokenId);
        roles[resource][owner] = roleBitmap;
        
        emit NewSubname(tokenId, label);
        return tokenId;
    }
    
    function renew(uint256 tokenId, uint64 newExpiry) external {
        require(roles[ROOT_RESOURCE][msg.sender] & ROLE_RENEW != 0 || 
                roles[bytes32(tokenId)][msg.sender] & ROLE_RENEW != 0, "Not authorized");
        
        require(expirations[tokenId] <= newExpiry, "Cannot reduce expiration");
        expirations[tokenId] = newExpiry;
        
        // Notify observer if exists
        if (address(tokenObservers[tokenId]) != address(0)) {
            tokenObservers[tokenId].onRenew(tokenId, newExpiry, msg.sender);
        }
        
        emit NameRenewed(tokenId, newExpiry, msg.sender);
    }
    
    function relinquish(uint256 tokenId) external {
        require(owners[tokenId] == msg.sender, "Not owner");
        
        // Notify observer if exists
        if (address(tokenObservers[tokenId]) != address(0)) {
            tokenObservers[tokenId].onRelinquish(tokenId, msg.sender);
        }
        
        registered[tokenId] = false;
        owners[tokenId] = address(0);
        subregistries[tokenId] = IRegistry(address(0));
        resolvers[tokenId] = address(0);
        expirations[tokenId] = 0;
        
        // Clear roles for token
        bytes32 resource = bytes32(tokenId);
        roles[resource][msg.sender] = 0;
        
        emit NameRelinquished(tokenId, msg.sender);
    }
    
    function setSubregistry(uint256 tokenId, IRegistry subregistry) external {
        require(roles[bytes32(tokenId)][msg.sender] & ROLE_SET_SUBREGISTRY != 0, "Not authorized");
        subregistries[tokenId] = subregistry;
    }
    
    function setResolver(uint256 tokenId, address resolver) external {
        require(roles[bytes32(tokenId)][msg.sender] & ROLE_SET_RESOLVER != 0, "Not authorized");
        resolvers[tokenId] = resolver;
    }
    
    function setTokenObserver(uint256 tokenId, ITokenObserver observer) external {
        require(roles[bytes32(tokenId)][msg.sender] & ROLE_SET_TOKEN_OBSERVER != 0, "Not authorized");
        tokenObservers[tokenId] = observer;
        emit TokenObserverSet(tokenId, address(observer));
    }
    
    function getExpiry(uint256 tokenId) external view returns (uint64) {
        return expirations[tokenId];
    }
    
    function getNameData(string calldata label) external view returns (uint256 tokenId, uint64 expiry, uint32 tokenIdVersion) {
        tokenId = uint256(keccak256(abi.encodePacked(label)));
        expiry = expirations[tokenId];
        tokenIdVersion = 0; // Using 0 for simplicity in mocks
    }
    
    function ownerOf(uint256 tokenId) external view returns (address) {
        if (expirations[tokenId] < block.timestamp) {
            return address(0); // Expired name has no owner
        }
        return owners[tokenId];
    }
    
    function getSubregistry(string calldata label) external view returns (IRegistry) {
        uint256 tokenId = uint256(keccak256(abi.encodePacked(label)));
        if (expirations[tokenId] < block.timestamp) {
            return IRegistry(address(0)); // Expired name has no subregistry
        }
        return subregistries[tokenId];
    }
    
    function getResolver(string calldata label) external view returns (address) {
        uint256 tokenId = uint256(keccak256(abi.encodePacked(label)));
        if (expirations[tokenId] < block.timestamp) {
            return address(0); // Expired name has no resolver
        }
        return resolvers[tokenId];
    }
    
    function getTokenIdResource(uint256 tokenId) external pure returns (bytes32) {
        return bytes32(tokenId);
    }
    
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes memory data) external {
        require(owners[id] == from, "Not owner");
        owners[id] = to;
        
        // Transfer roles
        bytes32 resource = bytes32(id);
        roles[resource][to] = roles[resource][from];
        roles[resource][from] = 0;
    }
    
    function balanceOf(address account, uint256 id) external view returns (uint256) {
        return owners[id] == account ? 1 : 0;
    }
    
    // EnhancedAccessControl required methods
    function hasRoles(bytes32 resource, uint256 rolesBitmap, address account) external view returns (bool) {
        return (roles[resource][account] & rolesBitmap) == rolesBitmap ||
               (roles[ROOT_RESOURCE][account] & rolesBitmap) == rolesBitmap;
    }
    
    function hasRootRoles(uint256 rolesBitmap, address account) external view returns (bool) {
        return (roles[ROOT_RESOURCE][account] & rolesBitmap) == rolesBitmap;
    }
    
    function grantRootRoles(uint256 rolesBitmap, address account) external returns (bool) {
        roles[ROOT_RESOURCE][account] |= rolesBitmap;
        return true;
    }
    
    function grantRoles(bytes32 resource, uint256 rolesBitmap, address account) external returns (bool) {
        roles[resource][account] |= rolesBitmap;
        return true;
    }
    
    function revokeRootRoles(uint256 rolesBitmap, address account) external returns (bool) {
        roles[ROOT_RESOURCE][account] &= ~rolesBitmap;
        return true;
    }
    
    function revokeRoles(bytes32 resource, uint256 rolesBitmap, address account) external returns (bool) {
        roles[resource][account] &= ~rolesBitmap;
        return true;
    }
}

contract BridgeTest is Test {
    // Components for the test
    SimpleMockRegistry l1Registry;
    SimpleMockRegistry l2Registry;
    MockBridgeHelper bridgeHelper;
    MockL1Bridge l1Bridge;
    MockL2Bridge l2Bridge;
    MockL1EjectionController l1Controller;
    MockL2EjectionController l2Controller;
    
    // Test accounts
    address user1 = address(0x1);
    address user2 = address(0x2);
    
    function setUp() public {
        // Deploy the contracts
        l1Registry = new SimpleMockRegistry();
        l2Registry = new SimpleMockRegistry();
        
        bridgeHelper = new MockBridgeHelper();
        
        // Deploy bridges with bridge helper
        l1Bridge = new MockL1Bridge(address(0), address(bridgeHelper));
        l2Bridge = new MockL2Bridge(address(0), address(bridgeHelper));
        
        // Deploy controllers
        l1Controller = new MockL1EjectionController(address(l1Registry), address(bridgeHelper), address(l1Bridge));
        l2Controller = new MockL2EjectionController(address(l2Registry), address(bridgeHelper), address(l2Bridge));
        
        // Set the controller contracts as targets for the bridges
        l1Bridge.setTargetController(address(l1Controller));
        l2Bridge.setTargetController(address(l2Controller));
        
        // Grant ROLE_REGISTRAR and ROLE_RENEW to controllers
        l1Registry.grantRootRoles(l1Registry.ROLE_REGISTRAR() | l1Registry.ROLE_RENEW(), address(l1Controller));
        l2Registry.grantRootRoles(l2Registry.ROLE_REGISTRAR() | l2Registry.ROLE_RENEW(), address(l2Controller));
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
        
        l2Bridge.receiveMessageFromL1(message);
        
        // Verify owner is set correctly on L2
        uint256 tokenId = uint256(keccak256(abi.encodePacked(name)));
        assertEq(l2Registry.ownerOf(tokenId), l2Owner);
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
        
        // Now correctly expect the event with the name "premiumname.eth"
        uint256 labelHash = uint256(keccak256(abi.encodePacked(name)));
        vm.expectEmit(true, true, true, true);
        emit SimpleMockRegistry.NewSubname(labelHash, name);
        
        l1Bridge.receiveMessageFromL2(message);
        
        // Verify the name is registered on L1
        uint256 tokenId = uint256(keccak256(abi.encodePacked(name)));
        assertEq(l1Registry.ownerOf(tokenId), l1Owner);
    }
    
    function testCompleteRoundTrip() public {
        // Test a complete cycle: L1 -> L2 -> L1
        string memory name = "roundtrip.eth";
        uint256 tokenId = uint256(keccak256(abi.encodePacked(name)));
        
        // Step 1: Migrate from L1 to L2
        vm.startPrank(user1);
        l1Controller.requestMigration(name, user2, address(0x123));
        vm.stopPrank();
        
        // Simulate the relayer for L1->L2
        bytes memory migrationMsg = bridgeHelper.encodeMigrationMessage(name, user2, address(0x123));
        l2Bridge.receiveMessageFromL1(migrationMsg);
        
        // Verify name is on L2 owned by user2
        assertEq(l2Registry.ownerOf(tokenId), user2);
        
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
        assertEq(l1Registry.ownerOf(tokenId), user1);
    }
}
