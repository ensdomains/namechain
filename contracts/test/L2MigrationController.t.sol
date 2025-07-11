// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {L2MigrationController} from "../src/L2/L2MigrationController.sol";
import {L2EjectionController} from "../src/L2/L2EjectionController.sol";
import {PermissionedRegistry} from "../src/common/PermissionedRegistry.sol";
import {RegistryDatastore} from "../src/common/RegistryDatastore.sol";
import {IRegistryDatastore} from "../src/common/IRegistryDatastore.sol";
import {IRegistryMetadata} from "../src/common/IRegistryMetadata.sol";
import {SimpleRegistryMetadata} from "../src/common/SimpleRegistryMetadata.sol";
import {RegistryFactory} from "../src/common/RegistryFactory.sol";
import {IRegistryFactory} from "../src/common/IRegistryFactory.sol";
import {TransferData, MigrationData} from "../src/common/TransferData.sol";
import {IBridge} from "../src/common/IBridge.sol";
import {IPermissionedRegistry} from "../src/common/IPermissionedRegistry.sol";
import {ITokenObserver} from "../src/common/ITokenObserver.sol";
import {IRegistry} from "../src/common/IRegistry.sol";
import {NameUtils} from "../src/common/NameUtils.sol";
import {TestUtils} from "./utils/TestUtils.sol";

// Mock implementation of IRegistryMetadata
contract MockRegistryMetadata is IRegistryMetadata {
    function tokenUri(uint256) external pure override returns (string memory) {
        return "";
    }
}

// Mock implementation of IBridge for testing
contract MockBridge is IBridge {
    uint256 public sendMessageCallCount;
    bytes public lastMessage;

    function sendMessage(bytes memory message) external override {
        sendMessageCallCount++;
        lastMessage = message;
    }

    function resetCounters() external {
        sendMessageCallCount = 0;
        lastMessage = "";
    }
}

// Mock implementation of L2EjectionController for testing
contract MockL2EjectionController is L2EjectionController {
    event MockEjectionFromMigrationController(uint256 tokenId, TransferData transferData);

    constructor(IPermissionedRegistry _registry, IBridge _bridge) L2EjectionController(_registry, _bridge) {}

    // Override _onEject to emit a test event when migration controller transfers to us
    function _onEject(address from, uint256[] memory tokenIds, TransferData[] memory transferDataArray) internal override {
        // Call parent implementation first
        super._onEject(from, tokenIds, transferDataArray);
        
        // If the transfer is from an address with migration controller role, emit test event
        if (hasRoles(ROOT_RESOURCE, ROLE_MIGRATION_CONTROLLER, from)) {
            for (uint256 i = 0; i < tokenIds.length; i++) {
                emit MockEjectionFromMigrationController(tokenIds[i], transferDataArray[i]);
            }
        }
    }

    // Implement required virtual functions
    function onRenew(uint256, uint64, address) external override {}
    function onRelinquish(uint256, address) external override {}
}

contract TestL2MigrationController is Test {
    L2MigrationController migrationController;
    MockBridge bridge;
    MockL2EjectionController ejectionController;
    PermissionedRegistry ethRegistry;
    RegistryDatastore datastore;
    MockRegistryMetadata registryMetadata;
    RegistryFactory registryFactory;

    address user = address(0x1);
    address owner = address(0x2);
    address resolver = address(0x3);
    
    string testLabel = "test";
    string subdLabel = "sub";
    bytes32 constant ETH_TLD_HASH = keccak256(bytes("eth"));
    
    uint64 expiryDuration = 86400; // 1 day

    function setUp() public {
        // Deploy dependencies
        datastore = new RegistryDatastore();
        registryMetadata = new MockRegistryMetadata();
        bridge = new MockBridge();
        
        // Deploy registry factory
        registryFactory = new RegistryFactory();
        
        // Deploy ETH registry
        ethRegistry = new PermissionedRegistry(datastore, registryMetadata, address(this), TestUtils.ALL_ROLES);
        
        // Deploy ejection controller
        ejectionController = new MockL2EjectionController(ethRegistry, bridge);
        
        // Deploy migration controller
        migrationController = new L2MigrationController(
            address(bridge), 
            ejectionController,
            ethRegistry, 
            datastore,
            registryFactory
        );
        
        // Grant roles to migration controller for registering names
        ethRegistry.grantRootRoles(1 << 0, address(migrationController)); // ROLE_REGISTRAR
        
        // Grant migration controller role to the migration controller for the ejection controller
        // This allows the migration controller to transfer tokens without triggering bridge messages
        ejectionController.grantRootRoles(1 << 0, address(migrationController)); // ROLE_MIGRATION_CONTROLLER
    }

    /**
     * Helper method to create properly encoded DNS name for testing
     */
    function _createDnsEncodedName(string memory label) internal pure returns (bytes memory) {
        return NameUtils.dnsEncodeEthLabel(label);
    }

    /**
     * Helper method to create properly encoded DNS name with subdomains
     */
    function _createDnsEncodedSubdomainName(string memory subdomain, string memory label) internal pure returns (bytes memory) {
        return abi.encodePacked(
            bytes1(uint8(bytes(subdomain).length)), subdomain,
            bytes1(uint8(bytes(label).length)), label,
            "\x03eth\x00"
        );
    }

    /**
     * Helper method to create migration data
     */
    function _createMigrationData(
        string memory label,
        address migrationOwner,
        address subregistry,
        address migrationResolver,
        uint256 roleBitmap,
        uint64 expires,
        bool toL1
    ) internal pure returns (MigrationData memory) {
        return MigrationData({
            transferData: TransferData({
                label: label,
                owner: migrationOwner,
                subregistry: subregistry,
                resolver: migrationResolver,
                roleBitmap: roleBitmap,
                expires: expires
            }),
            toL1: toL1,
            data: ""
        });
    }

    /**
     * Helper method to register a subdomain to create the registry tree structure
     */
    function _registerSubdomain(string memory label, address subdomainOwner) internal returns (uint256) {
        return ethRegistry.register(
            label, 
            subdomainOwner, 
            ethRegistry, 
            address(0), 
            TestUtils.ALL_ROLES, 
            uint64(block.timestamp + expiryDuration)
        );
    }

    /**
     * Helper method to verify MigrationCompleted event
     */
    function _assertMigrationCompletedEvent(bytes memory expectedDnsName, uint256 expectedTokenId) internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        
        bytes32 eventSig = keccak256("MigrationCompleted(bytes,uint256)");
        
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(migrationController) && 
                logs[i].topics[0] == eventSig) {
                (bytes memory emittedDnsName, uint256 emittedTokenId) = 
                    abi.decode(logs[i].data, (bytes, uint256));
                
                if (keccak256(emittedDnsName) == keccak256(expectedDnsName) && 
                    emittedTokenId == expectedTokenId) {
                    foundEvent = true;
                    break;
                }
            }
        }
        assertTrue(foundEvent, "MigrationCompleted event not found");
    }



    /**
     * Helper method to verify that no bridge message was sent (for migration transfers)
     */
    function _assertNoBridgeMessage() internal view {
        assertEq(bridge.sendMessageCallCount(), 0, "Bridge message should not be sent for migration transfers");
    }

    /**
     * Helper method to verify that no NameEjectedToL1 event was emitted (for migration transfers)
     */
    function _assertNoNameEjectedToL1Event() internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSig = keccak256("NameEjectedToL1(bytes,uint256)");
        
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(ejectionController) && 
                logs[i].topics[0] == eventSig) {
                assertTrue(false, "NameEjectedToL1 event should not be emitted for migration transfers");
            }
        }
    }

    function test_constructor() public view {
        assertEq(address(migrationController.bridge()), address(bridge));
        assertEq(address(migrationController.ejectionController()), address(ejectionController));
        assertEq(address(migrationController.ethRegistry()), address(ethRegistry));
        assertEq(address(migrationController.datastore()), address(datastore));
        assertEq(address(migrationController.registryFactory()), address(registryFactory));
        assertEq(migrationController.ETH_TLD_HASH(), ETH_TLD_HASH);
        assertEq(migrationController.owner(), address(this));
    }

    function test_completeMigrationFromL1_toL2Only() public {
        bytes memory dnsEncodedName = _createDnsEncodedName(testLabel);
        uint64 expires = uint64(block.timestamp + expiryDuration);
        
        MigrationData memory migrationData = _createMigrationData(
            testLabel,
            user,
            address(0),
            resolver,
            TestUtils.ALL_ROLES,
            expires,
            false // toL1 = false, L2 only
        );
        
        vm.recordLogs();
        
        // Call from bridge
        vm.prank(address(bridge));
        migrationController.completeMigrationFromL1(dnsEncodedName, migrationData);
        
        // Verify the name was registered in the ETH registry
        (uint256 tokenId, uint64 registeredExpiry, ) = ethRegistry.getNameData(testLabel);
        assertEq(ethRegistry.ownerOf(tokenId), user, "User should own the registered token");
        assertEq(registeredExpiry, expires, "Expiry should match migration data");
        
        // Verify resolver was set
        assertEq(ethRegistry.getResolver(testLabel), resolver, "Resolver should be set correctly");
        
        // Verify MigrationCompleted event was emitted
        _assertMigrationCompletedEvent(dnsEncodedName, tokenId);
    }

    function test_completeMigrationFromL1_toL1AndL2() public {
        bytes memory dnsEncodedName = _createDnsEncodedName(testLabel);
        uint64 expires = uint64(block.timestamp + expiryDuration);
        
        MigrationData memory migrationData = _createMigrationData(
            testLabel,
            user,
            address(0),
            resolver,
            TestUtils.ALL_ROLES,
            expires,
            true // toL1 = true, both L1 and L2
        );
        
        // Reset bridge counter to check that no bridge message is sent
        bridge.resetCounters();
        
        vm.recordLogs();
        
        // Call from bridge
        vm.prank(address(bridge));
        migrationController.completeMigrationFromL1(dnsEncodedName, migrationData);
        
        // Verify the name was registered in the ETH registry
        (uint256 tokenId, uint64 registeredExpiry, ) = ethRegistry.getNameData(testLabel);
        assertEq(registeredExpiry, expires, "Expiry should match migration data");
        
        // When toL1 is true, the token should be owned by the ejection controller (after transfer)
        assertEq(ethRegistry.ownerOf(tokenId), address(ejectionController), "Ejection controller should own the token after transfer");
        
        // Verify resolver was set
        assertEq(ethRegistry.getResolver(testLabel), resolver, "Resolver should be set correctly");
        
        // Verify MigrationCompleted event was emitted
        _assertMigrationCompletedEvent(dnsEncodedName, tokenId);
        
        // Verify no bridge message was sent (migration transfers should skip bridge)
        _assertNoBridgeMessage();
        
        // Verify no NameEjectedToL1 event was emitted (migration transfers should skip this)
        _assertNoNameEjectedToL1Event();
    }

    function test_completeMigrationFromL1_withSubdomain() public {
        // First register the subdomain
        _registerSubdomain(subdLabel, user);
        
        // Now try to migrate a name under the subdomain
        bytes memory dnsEncodedName = _createDnsEncodedSubdomainName("nested", subdLabel);
        uint64 expires = uint64(block.timestamp + expiryDuration);
        
        MigrationData memory migrationData = _createMigrationData(
            "nested",
            user,
            address(0),
            resolver,
            TestUtils.ALL_ROLES,
            expires,
            false
        );
        
        vm.recordLogs();
        
        // Call from bridge
        vm.prank(address(bridge));
        migrationController.completeMigrationFromL1(dnsEncodedName, migrationData);
        
        // Verify the nested name was registered in the subdomain registry
        (uint256 tokenId, uint64 registeredExpiry, ) = ethRegistry.getNameData("nested");
        assertEq(ethRegistry.ownerOf(tokenId), user, "User should own the nested token");
        assertEq(registeredExpiry, expires, "Expiry should match migration data");
        
        // Verify MigrationCompleted event was emitted
        _assertMigrationCompletedEvent(dnsEncodedName, tokenId);
    }

    function test_Revert_completeMigrationFromL1_UnauthorizedCaller() public {
        bytes memory dnsEncodedName = _createDnsEncodedName(testLabel);
        MigrationData memory migrationData = _createMigrationData(
            testLabel,
            user,
            address(0),
            resolver,
            TestUtils.ALL_ROLES,
            uint64(block.timestamp + expiryDuration),
            false
        );
        
        // Try to call from non-bridge address
        vm.expectRevert(abi.encodeWithSelector(L2MigrationController.UnauthorizedCaller.selector, address(this)));
        migrationController.completeMigrationFromL1(dnsEncodedName, migrationData);
    }

    function test_Revert_completeMigrationFromL1_NameAlreadyRegistered() public {
        bytes memory dnsEncodedName = _createDnsEncodedName(testLabel);
        
        // First register the name
        _registerSubdomain(testLabel, user);
        
        MigrationData memory migrationData = _createMigrationData(
            testLabel,
            user,
            address(0),
            resolver,
            TestUtils.ALL_ROLES,
            uint64(block.timestamp + expiryDuration),
            false
        );
        
        // Try to migrate the already registered name
        vm.prank(address(bridge));
        vm.expectRevert(abi.encodeWithSelector(L2MigrationController.NameAlreadyRegistered.selector, dnsEncodedName));
        migrationController.completeMigrationFromL1(dnsEncodedName, migrationData);
    }

    function test_Revert_completeMigrationFromL1_InvalidTLD() public {
        // Create DNS encoded name with invalid TLD (not .eth)
        bytes memory invalidDnsName = abi.encodePacked(
            bytes1(uint8(bytes(testLabel).length)), testLabel,
            "\x03com\x00" // .com instead of .eth
        );
        
        MigrationData memory migrationData = _createMigrationData(
            testLabel,
            user,
            address(0),
            resolver,
            TestUtils.ALL_ROLES,
            uint64(block.timestamp + expiryDuration),
            false
        );
        
        bytes32 invalidTldHash = keccak256(bytes("com"));
        
        // Try to migrate with invalid TLD
        vm.prank(address(bridge));
        vm.expectRevert(abi.encodeWithSelector(L2MigrationController.InvalidTLD.selector, invalidTldHash));
        migrationController.completeMigrationFromL1(invalidDnsName, migrationData);
    }

    function test_Revert_completeMigrationFromL1_LabelNotFound() public {
        // Try to migrate a subdomain without registering the parent domain first
        bytes memory dnsEncodedName = _createDnsEncodedSubdomainName("nested", "nonexistent");
        
        MigrationData memory migrationData = _createMigrationData(
            "nested",
            user,
            address(0),
            resolver,
            TestUtils.ALL_ROLES,
            uint64(block.timestamp + expiryDuration),
            false
        );
        
        // Try to migrate under non-existent parent
        vm.prank(address(bridge));
        vm.expectRevert(abi.encodeWithSelector(L2MigrationController.LabelNotFound.selector, dnsEncodedName, "nonexistent"));
        migrationController.completeMigrationFromL1(dnsEncodedName, migrationData);
    }

    function test_completeMigrationFromL1_MultipleSubdomainLevels() public {
        // Register nested subdomains: sub.eth, then try to migrate deep.sub.eth
        _registerSubdomain(subdLabel, user);
        
        // Create a 3-level DNS name: deep.sub.eth
        bytes memory deepDnsName = abi.encodePacked(
            bytes1(uint8(bytes("deep").length)), "deep",
            bytes1(uint8(bytes(subdLabel).length)), subdLabel,
            "\x03eth\x00"
        );
        
        uint64 expires = uint64(block.timestamp + expiryDuration);
        
        MigrationData memory migrationData = _createMigrationData(
            "deep",
            user,
            address(0),
            resolver,
            TestUtils.ALL_ROLES,
            expires,
            false
        );
        
        vm.recordLogs();
        
        // Call from bridge
        vm.prank(address(bridge));
        migrationController.completeMigrationFromL1(deepDnsName, migrationData);
        
        // Verify the deep nested name was registered
        (uint256 tokenId, uint64 registeredExpiry, ) = ethRegistry.getNameData("deep");
        assertEq(ethRegistry.ownerOf(tokenId), user, "User should own the deep nested token");
        assertEq(registeredExpiry, expires, "Expiry should match migration data");
        
        // Verify MigrationCompleted event was emitted
        _assertMigrationCompletedEvent(deepDnsName, tokenId);
    }

    function test_completeMigrationFromL1_EmptySubregistry() public {
        bytes memory dnsEncodedName = _createDnsEncodedName(testLabel);
        uint64 expires = uint64(block.timestamp + expiryDuration);
        
        // Create migration data with zero subregistry address
        MigrationData memory migrationData = _createMigrationData(
            testLabel,
            user,
            address(0), // empty subregistry
            resolver,
            TestUtils.ALL_ROLES,
            expires,
            false
        );
        
        vm.recordLogs();
        
        // Call from bridge
        vm.prank(address(bridge));
        migrationController.completeMigrationFromL1(dnsEncodedName, migrationData);
        
        // Verify the name was registered successfully even with empty subregistry
        (uint256 tokenId, uint64 registeredExpiry, ) = ethRegistry.getNameData(testLabel);
        assertEq(ethRegistry.ownerOf(tokenId), user, "User should own the registered token");
        assertEq(registeredExpiry, expires, "Expiry should match migration data");
        
        // Verify MigrationCompleted event was emitted
        _assertMigrationCompletedEvent(dnsEncodedName, tokenId);
    }

    function test_completeMigrationFromL1_ZeroRoleBitmap() public {
        bytes memory dnsEncodedName = _createDnsEncodedName(testLabel);
        uint64 expires = uint64(block.timestamp + expiryDuration);
        
        // Create migration data with zero role bitmap
        MigrationData memory migrationData = _createMigrationData(
            testLabel,
            user,
            address(0),
            resolver,
            0, // zero role bitmap
            expires,
            false
        );
        
        vm.recordLogs();
        
        // Call from bridge
        vm.prank(address(bridge));
        migrationController.completeMigrationFromL1(dnsEncodedName, migrationData);
        
        // Verify the name was registered successfully even with zero roles
        (uint256 tokenId, uint64 registeredExpiry, ) = ethRegistry.getNameData(testLabel);
        assertEq(ethRegistry.ownerOf(tokenId), user, "User should own the registered token");
        assertEq(registeredExpiry, expires, "Expiry should match migration data");
        
        // Verify MigrationCompleted event was emitted
        _assertMigrationCompletedEvent(dnsEncodedName, tokenId);
    }

    function test_onlyOwner_functions() public {
        // Test that Ownable functions work correctly (inherited from Ownable)
        assertEq(migrationController.owner(), address(this));
        
        // Test transferring ownership
        address newOwner = address(0x9999);
        migrationController.transferOwnership(newOwner);
        assertEq(migrationController.owner(), newOwner);
        
        // Test that previous owner can't transfer again
        vm.expectRevert();
        migrationController.transferOwnership(address(this));
        
        // New owner can transfer back
        vm.prank(newOwner);
        migrationController.transferOwnership(address(this));
        assertEq(migrationController.owner(), address(this));
    }

    function test_constants() public view {
        // Test that ETH_TLD_HASH constant is correct
        assertEq(migrationController.ETH_TLD_HASH(), keccak256(bytes("eth")));
    }

    function test_ejectionController_bridgeMessage_sentForRegularUsers() public {
        // Test that regular users (without ROLE_MIGRATION_CONTROLLER) still trigger bridge messages
        
        // Register a name to a regular user
        uint256 tokenId = _registerSubdomain(testLabel, user);
        
        // Create transfer data for ejection
        TransferData memory transferData = TransferData({
            label: testLabel,
            owner: user,
            subregistry: address(0),
            resolver: resolver,
            roleBitmap: TestUtils.ALL_ROLES,
            expires: uint64(block.timestamp + expiryDuration)
        });
        
        bytes memory transferDataBytes = abi.encode(transferData);
        
        // Reset bridge counter
        bridge.resetCounters();
        
        vm.recordLogs();
        
        // User transfers token to ejection controller (should trigger bridge message)
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(ejectionController), tokenId, 1, transferDataBytes);
        
        // Verify bridge message was sent (regular users should trigger bridge messages)
        assertEq(bridge.sendMessageCallCount(), 1, "Bridge message should be sent for regular user transfers");
        
        // Verify NameEjectedToL1 event was emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        bytes32 eventSig = keccak256("NameEjectedToL1(bytes,uint256)");
        
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(ejectionController) && 
                logs[i].topics[0] == eventSig) {
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "NameEjectedToL1 event should be emitted for regular user transfers");
    }
} 