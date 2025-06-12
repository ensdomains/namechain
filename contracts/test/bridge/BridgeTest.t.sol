// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";
import "../../src/mocks/MockL1Bridge.sol";
import "../../src/mocks/MockL2Bridge.sol";
import "../../src/mocks/MockL1EjectionController.sol";
import "../../src/mocks/MockL2EjectionController.sol";
import "../../src/mocks/MockBaseBridge.sol";
import {BridgeEncoder, BridgeMessageType} from "../../src/common/IBridge.sol";
import {TransferData, MigrationData} from "../../src/common/TransferData.sol";
import {NameCoder} from "@ens/contracts/utils/NameCoder.sol";

import { IRegistry } from "../../src/common/IRegistry.sol";
import { IPermissionedRegistry } from "../../src/common/IPermissionedRegistry.sol";
import { PermissionedRegistry } from "../../src/common/PermissionedRegistry.sol";
import { ITokenObserver } from "../../src/common/ITokenObserver.sol";
import { EnhancedAccessControl } from "../../src/common/EnhancedAccessControl.sol";
import { RegistryDatastore } from "../../src/common/RegistryDatastore.sol";
import { IRegistryMetadata } from "../../src/common/IRegistryMetadata.sol";
import { RegistryRolesMixin } from "../../src/common/RegistryRolesMixin.sol";

contract BridgeTest is Test, EnhancedAccessControl, RegistryRolesMixin {
    RegistryDatastore datastore;
    PermissionedRegistry l1Registry;
    PermissionedRegistry l2Registry;
    MockL1Bridge l1Bridge;
    MockL2Bridge l2Bridge;
    MockL1EjectionController l1Controller;
    MockL2EjectionController l2Controller;
    
    // Test accounts
    address user1 = address(0x1);
    address user2 = address(0x2);
    
    function setUp() public {
        // Deploy the contracts
        datastore = new RegistryDatastore();
        l1Registry = new PermissionedRegistry(datastore, IRegistryMetadata(address(0)), ALL_ROLES);
        l2Registry = new PermissionedRegistry(datastore, IRegistryMetadata(address(0)), ALL_ROLES);
        
        // Deploy bridges
        l1Bridge = new MockL1Bridge();
        l2Bridge = new MockL2Bridge();
        
        // Deploy controllers
        l1Controller = new MockL1EjectionController(l1Registry, l1Bridge);
        l2Controller = new MockL2EjectionController(l2Registry, l2Bridge);
        
        // Set the controller contracts as targets for the bridges
        l1Bridge.setEjectionController(l1Controller);
        l2Bridge.setEjectionController(l2Controller);
        
        // Grant ROLE_REGISTRAR and ROLE_RENEW to controllers
        l1Registry.grantRootRoles(ROLE_REGISTRAR | ROLE_RENEW, address(l1Controller));
    }
    
    function testNameEjectionFromL2ToL1() public {
        string memory name = "premiumname.eth";
        uint256 tokenId = l2Registry.register(name, user2, IRegistry(address(0x456)), address(0x789), ALL_ROLES, uint64(block.timestamp + 365 days));

        TransferData memory transferData = TransferData({
            label: name,
            owner: user2,
            subregistry: address(0x123),
            resolver: address(0x456),
            expires: uint64(block.timestamp + 123 days),
            roleBitmap: ROLE_RENEW
        });

        vm.recordLogs();

        // Step 1: Initiate ejection on L2
        vm.startPrank(user2);
        l2Registry.safeTransferFrom(user2, address(l2Controller), tokenId, 1, abi.encode(transferData));
        vm.stopPrank();
        
        // Check for NameEjectedToL1 event from L2 bridge
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 ejectionEventSig = keccak256("NameEjectedToL1(bytes,bytes)");
        
        uint256 ejectionEventIndex = 0;
        for (ejectionEventIndex = 0; ejectionEventIndex < entries.length; ejectionEventIndex++) {
            if (entries[ejectionEventIndex].topics[0] == ejectionEventSig) {
                break;
            }
        }

        assertTrue(ejectionEventIndex < entries.length, "NameEjectedToL1 event not found");
        
        // Decode the NameEjectedToL1 event - dnsEncodedName in topics, data in data
        bytes32 eventDnsEncodedNameHash = entries[ejectionEventIndex].topics[1];
        bytes memory eventData = abi.decode(entries[ejectionEventIndex].data, (bytes));
        
        // Verify the DNS encoded name hash matches
        bytes memory expectedDnsEncodedName = NameCoder.encode(string.concat(name, ".eth"));
        assertEq(eventDnsEncodedNameHash, keccak256(expectedDnsEncodedName));
        
        // The event data should be the raw TransferData
        TransferData memory eventTransferData = abi.decode(eventData, (TransferData));
        
        assertEq(eventTransferData.owner, transferData.owner);
        assertEq(eventTransferData.subregistry, transferData.subregistry);
        assertEq(eventTransferData.expires, transferData.expires);

        vm.recordLogs();    

        // Reconstruct the bridge message to simulate what the relay would do
        bytes memory bridgeMessage = BridgeEncoder.encode(BridgeMessageType.EJECTION, expectedDnsEncodedName, eventData);
        l1Bridge.receiveMessage(bridgeMessage);

        entries = vm.getRecordedLogs();

        // Check for MessageProcessed event
        bytes32 processedSig = keccak256("MessageProcessed(bytes)");
        uint256 processedIndex = 0;
        for (processedIndex = 0; processedIndex < entries.length; processedIndex++) {
            if (entries[processedIndex].topics[0] == processedSig) {
                break;
            }
        }
        assertTrue(processedIndex < entries.length, "MessageProcessed event not found");

        // Check that name is registered on L1
        assertEq(l1Registry.ownerOf(tokenId), transferData.owner);
        assertEq(address(l1Registry.getSubregistry(transferData.label)), transferData.subregistry);
        assertEq(l1Registry.getResolver(transferData.label), transferData.resolver);
        assertEq(l1Registry.getExpiry(tokenId), transferData.expires);
        bytes32 rolesResource = l1Registry.getTokenIdResource(tokenId);
        address owner = transferData.owner;
        assertEq(l1Registry.roles(rolesResource, owner), transferData.roleBitmap);
    }
    
    function testL2BridgeRevertsMigrationMessages() public {
        // Test that L2 bridge properly rejects migration message types
        bytes memory migrationData = abi.encode("test migration data");
        bytes memory dnsEncodedName = NameCoder.encode("test.eth");
        bytes memory migrationMessage = BridgeEncoder.encode(BridgeMessageType.MIGRATION, dnsEncodedName, migrationData);
        
        // Should revert with MigrationNotSupported error
        vm.expectRevert(MockBaseBridge.MigrationNotSupported.selector);
        l2Bridge.sendMessage(migrationMessage);
    }
    
    function testL1BridgeRevertsMigrationMessages() public {
        // Test that L1 bridge properly rejects migration message types when receiving them
        bytes memory migrationData = abi.encode("test migration data");
        bytes memory dnsEncodedName = NameCoder.encode("test.eth");
        bytes memory migrationMessage = BridgeEncoder.encode(BridgeMessageType.MIGRATION, dnsEncodedName, migrationData);
        
        // Should revert with MigrationNotSupported error when receiving migration messages
        vm.expectRevert(MockBaseBridge.MigrationNotSupported.selector);
        l1Bridge.receiveMessage(migrationMessage);
    }
    
    function testL1BridgeMigrationEvents() public {
        // Test that L1 bridge properly emits migration events with simplified parameters
        string memory label = "migrationtest";
        
        TransferData memory transferData = TransferData({
            label: label,
            owner: user1,
            subregistry: address(0x111),
            resolver: address(0x222),
            expires: uint64(block.timestamp + 365 days),
            roleBitmap: ROLE_RENEW
        });
        
        MigrationData memory migrationData = MigrationData({
            transferData: transferData,
            toL1: false,
            data: abi.encode("additional migration data")
        });
        
        bytes memory encodedMigrationData = abi.encode(migrationData);
        bytes memory dnsEncodedName = NameCoder.encode(string.concat(label, ".eth"));
        bytes memory migrationMessage = BridgeEncoder.encode(BridgeMessageType.MIGRATION, dnsEncodedName, encodedMigrationData);
        
        vm.recordLogs();
        
        // Trigger the migration message via sendMessage (this should work and emit event)
        l1Bridge.sendMessage(migrationMessage);
        
        // Check for NameMigratedToL2 event from L1 bridge
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 migrationEventSig = keccak256("NameMigratedToL2(bytes,bytes)");
        
        uint256 migrationEventIndex = 0;
        for (migrationEventIndex = 0; migrationEventIndex < entries.length; migrationEventIndex++) {
            if (entries[migrationEventIndex].topics[0] == migrationEventSig) {
                break;
            }
        }

        assertTrue(migrationEventIndex < entries.length, "NameMigratedToL2 event not found");
        
        // Decode the NameMigratedToL2 event - dnsEncodedName in topics, data in data
        bytes32 eventDnsEncodedNameHash = entries[migrationEventIndex].topics[1];
        bytes memory eventData = abi.decode(entries[migrationEventIndex].data, (bytes));
        
        // Verify the DNS encoded name hash matches
        assertEq(eventDnsEncodedNameHash, keccak256(dnsEncodedName));
        
        // The event data should be the raw MigrationData
        MigrationData memory eventMigrationData = abi.decode(eventData, (MigrationData));
        
        assertEq(eventMigrationData.transferData.owner, transferData.owner);
        assertEq(eventMigrationData.transferData.subregistry, transferData.subregistry);
        assertEq(eventMigrationData.transferData.expires, transferData.expires);
        assertEq(eventMigrationData.toL1, false);
    }
}
