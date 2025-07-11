// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";
import "../../src/mocks/MockL1Bridge.sol";
import "../../src/mocks/MockL2Bridge.sol";
import "../../src/L1/L1EjectionController.sol";
import "../../src/L2/L2EjectionController.sol";
import "../../src/mocks/MockBridgeBase.sol";
import {BridgeMessageType} from "../../src/common/IBridge.sol";
import {BridgeEncoder} from "../../src/common/BridgeEncoder.sol";
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
    L1EjectionController l1Controller;
    L2EjectionController l2Controller;
    
    // Test accounts
    address user1 = address(0x1);
    address user2 = address(0x2);
    
    function setUp() public {
        // Deploy the contracts
        datastore = new RegistryDatastore();
        l1Registry = new PermissionedRegistry(datastore, IRegistryMetadata(address(0)), address(this), ALL_ROLES);
        l2Registry = new PermissionedRegistry(datastore, IRegistryMetadata(address(0)), address(this), ALL_ROLES);
        
        // Deploy bridges
        l1Bridge = new MockL1Bridge();
        l2Bridge = new MockL2Bridge();
        
        // Deploy controllers
        l1Controller = new L1EjectionController(l1Registry, l1Bridge);
        l2Controller = new L2EjectionController(l2Registry, l2Bridge);
        
        // Set the controller contracts as targets for the bridges
        l1Bridge.setEjectionController(l1Controller);
        l2Bridge.setEjectionController(l2Controller);
        
        // Grant ROLE_REGISTRAR and ROLE_RENEW to controllers
        l1Registry.grantRootRoles(ROLE_REGISTRAR | ROLE_RENEW, address(l1Controller));
    }
    
    function testNameEjectionFromL2ToL1() public {
        // Register using just the label, as would be done in an .eth registry
        uint256 tokenId = l2Registry.register("premiumname", user2, IRegistry(address(0x456)), address(0x789), ALL_ROLES, uint64(block.timestamp + 365 days));

        TransferData memory transferData = TransferData({
            label: "premiumname",
            owner: user2,
            subregistry: address(0x123),
            resolver: address(0x456),
            expires: uint64(block.timestamp + 123 days),
            roleBitmap: ROLE_RENEW
        });

        // Step 1: Initiate ejection on L2
        vm.startPrank(user2);
        l2Registry.safeTransferFrom(user2, address(l2Controller), tokenId, 1, abi.encode(transferData));
        vm.stopPrank();
        
        // Step 2: Simulate receiving the message on L1
        bytes memory dnsEncodedName = NameCoder.encode("premiumname.eth");
        bytes memory bridgeMessage = BridgeEncoder.encodeEjection(dnsEncodedName, transferData);
        l1Bridge.receiveMessage(bridgeMessage);

        // Step 3: Verify the name is registered on L1
        assertEq(l1Registry.ownerOf(tokenId), transferData.owner);
        assertEq(address(l1Registry.getSubregistry("premiumname")), transferData.subregistry);
        assertEq(l1Registry.getResolver("premiumname"), transferData.resolver);
        assertEq(l1Registry.getExpiry(tokenId), transferData.expires);
        assertEq(l1Registry.roles(l1Registry.getTokenIdResource(tokenId), transferData.owner), transferData.roleBitmap);
    }
    
    function testL2BridgeRevertsMigrationMessages() public {
        // Test that L2 bridge properly rejects migration message types
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                label: "test",
                owner: user1,
                subregistry: address(0),
                resolver: address(0),
                expires: uint64(block.timestamp + 365 days),
                roleBitmap: 0
            }),
            toL1: false,
            data: abi.encode("test migration data")
        });
        bytes memory dnsEncodedName = NameCoder.encode("test.eth");
        bytes memory migrationMessage = BridgeEncoder.encodeMigration(dnsEncodedName, migrationData);
        
        // Should revert with MigrationNotSupported error
        vm.expectRevert(MockBridgeBase.MigrationNotSupported.selector);
        l2Bridge.sendMessage(migrationMessage);
    }
    
    function testL1BridgeRevertsMigrationMessages() public {
        // Test that L1 bridge properly rejects migration message types when receiving them
        MigrationData memory migrationData = MigrationData({
            transferData: TransferData({
                label: "test",
                owner: user1,
                subregistry: address(0),
                resolver: address(0),
                expires: uint64(block.timestamp + 365 days),
                roleBitmap: 0
            }),
            toL1: false,
            data: abi.encode("test migration data")
        });
        bytes memory dnsEncodedName = NameCoder.encode("test.eth");
        bytes memory migrationMessage = BridgeEncoder.encodeMigration(dnsEncodedName, migrationData);
        
        // Should revert with MigrationNotSupported error when receiving migration messages
        vm.expectRevert(MockBridgeBase.MigrationNotSupported.selector);
        l1Bridge.receiveMessage(migrationMessage);
    }
    
    function testL1BridgeMigrationEvents() public {
        // Test that L1 bridge properly emits NameBridgedToL2 events
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
        
        bytes memory dnsEncodedName = NameCoder.encode(string.concat(label, ".eth"));
        bytes memory migrationMessage = BridgeEncoder.encodeMigration(dnsEncodedName, migrationData);
        
        vm.recordLogs();
        
        // Trigger the migration message via sendMessage (this should work and emit event)
        l1Bridge.sendMessage(migrationMessage);
        
        // Check for NameBridgedToL2 event from L1 bridge
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 bridgeEventSig = keccak256("NameBridgedToL2(bytes)");
        
        bool foundBridgeEvent = false;
        uint256 bridgeEventIndex = 0;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == bridgeEventSig) {
                foundBridgeEvent = true;
                bridgeEventIndex = i;
                break;
            }
        }

        assertTrue(foundBridgeEvent, "NameBridgedToL2 event not found");
        
        // For NameBridgedToL2(bytes message) - single parameter is NOT indexed
        // so the message is in the data field
        (bytes memory eventMessage) = abi.decode(entries[bridgeEventIndex].data, (bytes));
        
        // Verify the message matches what we sent
        assertEq(keccak256(eventMessage), keccak256(migrationMessage));
        
        // Verify we can decode the message back to get the original data
        (bytes memory decodedDnsEncodedName, MigrationData memory decodedMigrationData) = BridgeEncoder.decodeMigration(eventMessage);
        assertEq(keccak256(decodedDnsEncodedName), keccak256(dnsEncodedName));
        assertEq(decodedMigrationData.transferData.owner, transferData.owner);
        assertEq(decodedMigrationData.transferData.subregistry, transferData.subregistry);
        assertEq(decodedMigrationData.transferData.expires, transferData.expires);
        assertEq(decodedMigrationData.toL1, false);
    }
}
