// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";
import "../../src/mocks/MockL1Bridge.sol";
import "../../src/mocks/MockL2Bridge.sol";
import "../../src/mocks/MockBridgeHelper.sol";
import "../../src/mocks/MockL1EjectionController.sol";
import "../../src/mocks/MockL2EjectionController.sol";

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
        datastore = new RegistryDatastore();
        l1Registry = new PermissionedRegistry(datastore, IRegistryMetadata(address(0)), ALL_ROLES);
        l2Registry = new PermissionedRegistry(datastore, IRegistryMetadata(address(0)), ALL_ROLES);
        
        bridgeHelper = new MockBridgeHelper();
        
        // Deploy bridges with bridge helper
        l1Bridge = new MockL1Bridge(bridgeHelper);
        l2Bridge = new MockL2Bridge(bridgeHelper);
        
        // Deploy controllers
        l1Controller = new MockL1EjectionController(l1Registry, l1Bridge);
        l2Controller = new MockL2EjectionController(l2Registry, l2Bridge);
        
        // Set the controller contracts as targets for the bridges
        l1Bridge.setTargetController(l1Controller);
        l2Bridge.setTargetController(l2Controller);
        
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
        
        // check for name ejected event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 messageSig = keccak256("L2ToL1Message(bytes)");
        
        uint256 messageIndex = 0;
        for (messageIndex = 0; messageIndex < entries.length; messageIndex++) {
            if (entries[messageIndex].topics[0] == messageSig) {
                break;
            }
        }

        assertTrue(messageIndex < entries.length, "bridge message not found");
        bytes memory message = abi.decode(entries[messageIndex].data, (bytes));


        // decode message
        (uint256 msgTokenId, TransferData memory msgTransferData) = bridgeHelper.decodeEjectionMessage(message);
        assertEq(msgTokenId, tokenId);
        assertEq(msgTransferData.label, transferData.label);
        assertEq(msgTransferData.owner, transferData.owner);
        assertEq(msgTransferData.subregistry, transferData.subregistry);
        assertEq(msgTransferData.resolver, transferData.resolver);
        assertEq(msgTransferData.expires, transferData.expires);
        assertEq(msgTransferData.roleBitmap, transferData.roleBitmap);

        vm.recordLogs();    

        // now let's simulate the bridge by calling the L1 bridge with the message
        l1Bridge.receiveMessageFromL2(message);

        entries = vm.getRecordedLogs();

        // check for MessageProcessed event
        messageSig = keccak256("MessageProcessed(bytes)");
        for (messageIndex = 0; messageIndex < entries.length; messageIndex++) {
            if (entries[messageIndex].topics[0] == messageSig) {
                break;
            }
        }
        assertTrue(messageIndex < entries.length, "MessageProcessed event not found");

        // check that name is registered on L1
        assertEq(l1Registry.ownerOf(tokenId), transferData.owner);
        assertEq(address(l1Registry.getSubregistry(transferData.label)), transferData.subregistry);
        assertEq(l1Registry.getResolver(transferData.label), transferData.resolver);
        assertEq(l1Registry.getExpiry(tokenId), transferData.expires);
        bytes32 rolesResource = l1Registry.getTokenIdResource(tokenId);
        assertEq(l1Registry.roles(rolesResource, transferData.owner), transferData.roleBitmap);
    }
    
    // function testNameMigrationFromL1ToL2() public {
    //     string memory name = "examplename.eth";
    //     address l2Owner = user2;
    //     address l2Subregistry = address(0x123);
        
    //     // Step 1: Initiate migration on L1
    //     vm.startPrank(user1);
    //     l1Controller.requestMigration(name, l2Owner, l2Subregistry);
    //     vm.stopPrank();
        
    //     // Step 2: In a real scenario, a relayer would observe the L1 event and call L2
    //     // For testing, we simulate this by directly calling the L2 bridge
    //     bytes memory message = bridgeHelper.encodeMigrationMessage(name, l2Owner, l2Subregistry);
        
    //     l2Bridge.receiveMessageFromL1(message);
        
    //     // Verify owner is set correctly on L2
    //     uint256 tokenId = uint256(keccak256(abi.encodePacked(name)));
    //     assertEq(l2Registry.ownerOf(tokenId), l2Owner);
    // }

    // function testCompleteRoundTrip() public {
    //     // Test a complete cycle: L1 -> L2 -> L1
    //     string memory name = "roundtrip.eth";
    //     uint256 tokenId = uint256(keccak256(abi.encodePacked(name)));
        
    //     // Step 1: Migrate from L1 to L2
    //     vm.startPrank(user1);
    //     l1Controller.requestMigration(name, user2, address(0x123));
    //     vm.stopPrank();
        
    //     // Simulate the relayer for L1->L2
    //     bytes memory migrationMsg = bridgeHelper.encodeMigrationMessage(name, user2, address(0x123));
    //     l2Bridge.receiveMessageFromL1(migrationMsg);
        
    //     // Verify name is on L2 owned by user2
    //     assertEq(l2Registry.ownerOf(tokenId), user2);
        
    //     // Step 2: Now eject from L2 back to L1
    //     vm.startPrank(user2);
    //     l2Controller.requestEjection(name, user1, address(0x456), uint64(block.timestamp + 365 days));
    //     vm.stopPrank();
        
    //     // Simulate the relayer for L2->L1
    //     bytes memory ejectionMsg = bridgeHelper.encodeEjectionMessage(
    //         name, 
    //         user1, 
    //         address(0x456), 
    //         uint64(block.timestamp + 365 days)
    //     );
    //     l1Bridge.receiveMessageFromL2(ejectionMsg);
        
    //     // Verify the results
    //     assertEq(l1Registry.ownerOf(tokenId), user1);
    // }
}
