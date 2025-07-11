// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";


import {L2BridgeController} from "../src/L2/L2BridgeController.sol";
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
import {RegistryRolesMixin} from "../src/common/RegistryRolesMixin.sol";
import {EjectionController} from "../src/common/EjectionController.sol";
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

// Test implementation of L2BridgeController with concrete methods for testing
contract TestL2BridgeControllerImpl is L2BridgeController {
    // Define event signatures exactly as they will be emitted
    event MockNameRenewed(uint256 indexed tokenId, uint64 expires, address renewedBy);
    event MockNameRelinquished(uint256 indexed tokenId, address relinquishedBy);

    // Tracking flags for callback tests
    bool private _onRenewCalled;
    bool private _onRelinquishCalled;

    constructor(
        IBridge _bridge,
        PermissionedRegistry _ethRegistry, 
        IRegistryDatastore _datastore,
        IRegistryFactory _registryFactory
    ) L2BridgeController(_bridge, _ethRegistry, _datastore, _registryFactory) {}

    // Implement the required external methods
    function onRenew(uint256 tokenId, uint64 expires, address renewedBy) external override {
        _onRenewCalled = true;
        emit MockNameRenewed(tokenId, expires, renewedBy);
    }
    
    function onRelinquish(uint256 tokenId, address relinquishedBy) external override {
        _onRelinquishCalled = true;
        emit MockNameRelinquished(tokenId, relinquishedBy);
    }

    // Helper functions for tests
    function resetTracking() external {
        _onRenewCalled = false;
        _onRelinquishCalled = false;
    }
    
    function onRenewCalled() external view returns (bool) {
        return _onRenewCalled;
    }
    
    function onRelinquishCalled() external view returns (bool) {
        return _onRelinquishCalled;
    }
}

contract TestL2BridgeController is Test, ERC1155Holder, RegistryRolesMixin {
    TestL2BridgeControllerImpl controller;
    PermissionedRegistry ethRegistry;
    RegistryDatastore datastore;
    MockRegistryMetadata registryMetadata;
    RegistryFactory registryFactory;
    MockBridge bridge;

    address user = address(0x1);
    address owner = address(0x2);
    address resolver = address(0x3);
    address l1Owner = address(0x2);
    address l1Subregistry = address(0x3);
    address l1Resolver = address(0x6);
    address l2Owner = address(0x4);
    address l2Subregistry = address(0x5);
    address l2Resolver = address(0x7);
    
    string testLabel = "test";
    string subdLabel = "sub";
    bytes32 constant ETH_TLD_HASH = keccak256(bytes("eth"));
    
    uint64 expiryDuration = 86400; // 1 day
    uint256 tokenId;

    function setUp() public {
        // Deploy dependencies
        datastore = new RegistryDatastore();
        registryMetadata = new MockRegistryMetadata();
        bridge = new MockBridge();
        
        // Deploy registry factory
        registryFactory = new RegistryFactory();
        
        // Deploy ETH registry
        ethRegistry = new PermissionedRegistry(datastore, registryMetadata, address(this), TestUtils.ALL_ROLES);
        
        // Deploy combined bridge controller
        controller = new TestL2BridgeControllerImpl(
            bridge,
            ethRegistry, 
            datastore,
            registryFactory
        );
        
        // Grant roles to bridge controller for registering names
        ethRegistry.grantRootRoles(1 << 0, address(controller)); // ROLE_REGISTRAR
        
        // Register a test name
        uint64 expires = uint64(block.timestamp + expiryDuration);
        tokenId = ethRegistry.register(testLabel, user, ethRegistry, address(0), TestUtils.ALL_ROLES, expires);
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
            if (logs[i].emitter == address(controller) && 
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
     * Helper method to create properly encoded data for the ERC1155 transfers
     */
    function _createEjectionData(
        string memory nameLabel,
        address _owner,
        address subregistry,
        address _resolver,
        uint64 expiryTime,
        uint256 roleBitmap
    ) internal pure returns (bytes memory) {
        TransferData memory transferData = TransferData({
            label: nameLabel,
            owner: _owner,
            subregistry: subregistry,
            resolver: _resolver,
            expires: expiryTime,
            roleBitmap: roleBitmap
        });
        return abi.encode(transferData);
    }

    // MIGRATION TESTS

    function test_constructor() public view {
        assertEq(address(controller.bridge()), address(bridge));
        assertEq(address(controller.ethRegistry()), address(ethRegistry));
        assertEq(address(controller.datastore()), address(datastore));
        assertEq(address(controller.registryFactory()), address(registryFactory));
        assertEq(controller.ETH_TLD_HASH(), ETH_TLD_HASH);

    }

    function test_completeMigrationFromL1_toL2Only() public {
        string memory migrationLabel = "migration";
        bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel(migrationLabel);
        uint64 expires = uint64(block.timestamp + expiryDuration);
        
        MigrationData memory migrationData = _createMigrationData(
            migrationLabel,
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
        controller.completeMigrationFromL1(dnsEncodedName, migrationData);
        
        // Verify the name was registered in the ETH registry
        (uint256 newTokenId, uint64 registeredExpiry, ) = ethRegistry.getNameData(migrationLabel);
        assertEq(ethRegistry.ownerOf(newTokenId), user, "User should own the registered token");
        assertEq(registeredExpiry, expires, "Expiry should match migration data");
        
        // Verify resolver was set
        assertEq(ethRegistry.getResolver(migrationLabel), resolver, "Resolver should be set correctly");
        
        // Verify MigrationCompleted event was emitted
        _assertMigrationCompletedEvent(dnsEncodedName, newTokenId);
    }

    function test_completeMigrationFromL1_toL1AndL2() public {
        string memory migrationLabel = "migrationl1";
        bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel(migrationLabel);
        uint64 expires = uint64(block.timestamp + expiryDuration);
        
        MigrationData memory migrationData = _createMigrationData(
            migrationLabel,
            user,
            address(0),
            resolver,
            TestUtils.ALL_ROLES,
            expires,
            true // toL1 = true, both L1 and L2
        );
        
        // Reset bridge counter to verify ejection message is sent
        bridge.resetCounters();
        
        vm.recordLogs();
        
        // Call from bridge
        vm.prank(address(bridge));
        controller.completeMigrationFromL1(dnsEncodedName, migrationData);
        
        // Verify the name was registered in the ETH registry
        (uint256 newTokenId, uint64 registeredExpiry, ) = ethRegistry.getNameData(migrationLabel);
        assertEq(registeredExpiry, expires, "Expiry should match migration data");
        
        // When toL1 is true, the token should be owned by the bridge controller (after ejection processing)
        assertEq(ethRegistry.ownerOf(newTokenId), address(controller), "Bridge controller should own the token after ejection");
        
        // Verify resolver was set
        assertEq(ethRegistry.getResolver(migrationLabel), resolver, "Resolver should be set correctly");
        
        // Verify MigrationCompleted event was emitted
        _assertMigrationCompletedEvent(dnsEncodedName, newTokenId);
        
        // Verify NO bridge message was sent (migration with toL1=true should not send bridge message)
        assertEq(bridge.sendMessageCallCount(), 0, "Bridge message should NOT be sent for toL1 migrations");
        
        // Verify subregistry was cleared (token marked as ejected)
        (address subregAddr, , ) = datastore.getSubregistry(newTokenId);
        assertEq(subregAddr, address(0), "Subregistry should be cleared for toL1 migrations");
        
        // Verify token observer was set
        assertEq(address(ethRegistry.tokenObservers(newTokenId)), address(controller), "Token observer should be set for toL1 migrations");
    }

    function test_Revert_completeMigrationFromL1_UnauthorizedCaller() public {
        bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel(testLabel);
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
        vm.expectRevert(abi.encodeWithSelector(EjectionController.UnauthorizedCaller.selector, address(this)));
        controller.completeMigrationFromL1(dnsEncodedName, migrationData);
    }

    function test_Revert_completeMigrationFromL1_NameAlreadyRegistered() public {
        bytes memory dnsEncodedName = NameUtils.dnsEncodeEthLabel(testLabel);
        
        // The test name is already registered in setUp()
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
        vm.expectRevert(abi.encodeWithSelector(L2BridgeController.NameAlreadyRegistered.selector, dnsEncodedName));
        controller.completeMigrationFromL1(dnsEncodedName, migrationData);
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
        vm.expectRevert(abi.encodeWithSelector(L2BridgeController.InvalidTLD.selector, invalidTldHash));
        controller.completeMigrationFromL1(invalidDnsName, migrationData);
    }

    // EJECTION TESTS

    function test_eject_flow_via_transfer() public {
        // Prepare the data for ejection with label and expiry
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint256 roleBitmap = TestUtils.ALL_ROLES;
        bytes memory ejectionData = _createEjectionData(testLabel, l1Owner, l1Subregistry, l1Resolver, expiryTime, roleBitmap);
        
        // Make sure user still owns the token
        assertEq(ethRegistry.ownerOf(tokenId), user);
        
        // User transfers the token to the bridge controller
        vm.recordLogs();
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);
        
        // Check for NameEjectedToL1 event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        
        bytes32 eventSig = keccak256("NameEjectedToL1(bytes,uint256)");
        
        for (uint i = 0; i < logs.length; i++) {
            // Check if this log is our event (emitter and first topic match)
            if (logs[i].emitter == address(controller) && 
                logs[i].topics[0] == eventSig) {
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "NameEjectedToL1 event not found");
        
        // Verify subregistry is cleared after ejection
        (address subregAddr, , ) = datastore.getSubregistry(tokenId);
        assertEq(subregAddr, address(0), "Subregistry not cleared after ejection");
        
        // Verify token observer is set
        assertEq(address(ethRegistry.tokenObservers(tokenId)), address(controller), "Token observer not set");
        
        // Verify token is now owned by the controller
        assertEq(ethRegistry.ownerOf(tokenId), address(controller), "Token should be owned by the controller");
    }

    function test_completeEjectionFromL1() public {
        // Use specific roles instead of ALL_ROLES
        uint256 originalRoles = ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY | ROLE_SET_TOKEN_OBSERVER;
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);

        string memory label2 = "test2";
        uint256 tokenId2 = ethRegistry.register(label2, user, ethRegistry, address(0), originalRoles, expiryTime);        
        
        // First eject the name so the controller owns it
        bytes memory ejectionData = _createEjectionData(label2, l1Owner, l1Subregistry, l1Resolver, expiryTime, originalRoles);
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), tokenId2, 1, ejectionData);
        
        // Verify controller owns the token
        assertEq(ethRegistry.ownerOf(tokenId2), address(controller), "Controller should own the token");
        
        // Try to migrate with different roles than the original ones - these should be ignored
        uint256 differentRoles = ROLE_RENEW | ROLE_REGISTRAR;
        vm.recordLogs();
        TransferData memory migrationData = TransferData({
            label: label2,
            owner: l2Owner,
            subregistry: l2Subregistry,
            resolver: l2Resolver,
            expires: 0,
            roleBitmap: differentRoles
        });
        
        // Call through the bridge (using vm.prank to simulate bridge calling)
        vm.prank(address(bridge));
        controller.completeEjectionFromL1(migrationData);
        
        // Verify migration results
        _verifyMigrationResults(tokenId2, label2, originalRoles, differentRoles);
        _verifyMigrationEvent(tokenId2, differentRoles);
    }
    
    // Helper function to verify migration results
    function _verifyMigrationResults(uint256 _tokenId, string memory _label, uint256 originalRoles, uint256 ignoredRoles) internal view {
        // Verify name was migrated - check ownership transfer
        assertEq(ethRegistry.ownerOf(_tokenId), l2Owner, "L2 owner should now own the token");
        
        // Verify subregistry and resolver were set correctly
        IRegistry subregAddr = ethRegistry.getSubregistry(_label);
        assertEq(address(subregAddr), l2Subregistry, "Subregistry not set correctly after migration");
        
        address resolverAddr = ethRegistry.getResolver(_label);
        assertEq(resolverAddr, l2Resolver, "Resolver not set correctly after migration");
        
        // ROLE BITMAP VERIFICATION:
        bytes32 resource = ethRegistry.getTokenIdResource(_tokenId);
        assertTrue(ethRegistry.hasRoles(resource, originalRoles, l2Owner), "L2 owner should have original roles");
        assertFalse(ethRegistry.hasRoles(resource, ignoredRoles, l2Owner), "L2 owner should not have new roles");
    }
    
    // Helper function to check for event emission
    function _verifyMigrationEvent(uint256 /* _tokenId */, uint256 /* expectedRoleBitmap */) internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        
        bytes32 eventSig = keccak256("NameEjectedToL2(bytes,uint256)");
        
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(controller) && 
                logs[i].topics[0] == eventSig) {
                foundEvent = true;
                break;
            }
        }
        
        assertTrue(foundEvent, "NameEjectedToL2 event not found");
    }

    function test_Revert_completeEjectionFromL1_notOwner() public {
        // Expect revert with NotTokenOwner error from the L2BridgeController logic
        vm.expectRevert(abi.encodeWithSelector(L2BridgeController.NotTokenOwner.selector, tokenId));
        // Call the external method which should revert
        TransferData memory migrationData = TransferData({
            label: testLabel,
            owner: l2Owner,
            subregistry: l2Subregistry,
            resolver: l2Resolver,
            expires: 0,
            roleBitmap: TestUtils.ALL_ROLES
        });
        // Call through the bridge (using vm.prank to simulate bridge calling)
        vm.prank(address(bridge));
        controller.completeEjectionFromL1(migrationData);
    }

    function test_Revert_completeEjectionFromL1_not_bridge() public {
        // Try to call completeEjectionFromL1 directly (not from bridge)
        TransferData memory transferData = TransferData({
            label: testLabel,
            owner: l2Owner,
            subregistry: l2Subregistry,
            resolver: l2Resolver,
            expires: 0,
            roleBitmap: TestUtils.ALL_ROLES
        });
        
        vm.expectRevert(abi.encodeWithSelector(EjectionController.UnauthorizedCaller.selector, address(this)));
        controller.completeEjectionFromL1(transferData);
    }

    function test_supportsInterface() public view {
        assertTrue(controller.supportsInterface(type(EjectionController).interfaceId));
        assertTrue(controller.supportsInterface(type(IERC1155Receiver).interfaceId));
        assertTrue(controller.supportsInterface(type(ITokenObserver).interfaceId));
        assertFalse(controller.supportsInterface(0x12345678));
    }

    function test_onRenew_emitsEvent() public {
        // First eject the name so the controller owns it and becomes the observer
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint32 roleBitmap = uint32(TestUtils.ALL_ROLES);
        bytes memory ejectionData = _createEjectionData(testLabel, l1Owner, l1Subregistry, l1Resolver, expiryTime, roleBitmap);
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);
        
        // Verify controller owns the token and is the observer
        assertEq(ethRegistry.ownerOf(tokenId), address(controller), "Controller should own the token");
        assertEq(address(ethRegistry.tokenObservers(tokenId)), address(controller), "Controller should be the observer");
        
        uint64 newExpiry = uint64(block.timestamp + expiryDuration * 2);
        address renewer = address(this);
        
        // Call onRenew directly on the controller (simulating a call from the registry)
        vm.recordLogs();
        controller.onRenew(tokenId, newExpiry, renewer);
        
        // Check for MockNameRenewed event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        
        bytes32 eventSig = keccak256("MockNameRenewed(uint256,uint64,address)");
        
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(controller) && 
                logs[i].topics[0] == eventSig) {
                
                // For indexed parameters, check that the topics match
                if (logs[i].topics.length > 1) {
                    assertEq(uint256(logs[i].topics[1]), tokenId, "Event tokenId should match");
                }
                
                // Only decode data if there is data to decode
                if (logs[i].data.length > 0) {
                    (uint64 emittedExpiry, address emittedRenewer) = 
                        abi.decode(logs[i].data, (uint64, address));
                    
                    assertEq(emittedExpiry, newExpiry, "Event expiry should match");
                    assertEq(emittedRenewer, renewer, "Event renewer should match");
                }
                
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "MockNameRenewed event not found");
    }

    function test_onRelinquish_emitsEvent() public {
        // First eject the name so the controller owns it and becomes the observer
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint32 roleBitmap = uint32(TestUtils.ALL_ROLES);
        bytes memory ejectionData = _createEjectionData(testLabel, l1Owner, l1Subregistry, l1Resolver, expiryTime, roleBitmap);
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);
        
        // Verify controller owns the token and is the observer
        assertEq(ethRegistry.ownerOf(tokenId), address(controller), "Controller should own the token");
        assertEq(address(ethRegistry.tokenObservers(tokenId)), address(controller), "Controller should be the observer");
        
        address relinquisher = address(this);
        
        // Call onRelinquish directly on the controller (simulating a call from the registry)
        vm.recordLogs();
        controller.onRelinquish(tokenId, relinquisher);
        
        // Check for MockNameRelinquished event
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool foundEvent = false;
        
        bytes32 eventSig = keccak256("MockNameRelinquished(uint256,address)");
        
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(controller) && 
                logs[i].topics[0] == eventSig) {
                
                // For indexed parameters, check that the topics match
                if (logs[i].topics.length > 1) {
                    assertEq(uint256(logs[i].topics[1]), tokenId, "Event tokenId should match");
                }
                
                // Only decode data if there is data to decode
                if (logs[i].data.length > 0) {
                    address emittedRelinquisher = abi.decode(logs[i].data, (address));
                    assertEq(emittedRelinquisher, relinquisher, "Event relinquisher should match");
                }
                
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "MockNameRelinquished event not found");
        
        // Verify token is still owned by the controller (onRelinquish in mock doesn't change ownership)
        assertEq(ethRegistry.ownerOf(tokenId), address(controller), "Token should still be owned by controller");
    }

    function test_Revert_eject_invalid_label() public {
        // Prepare the data for ejection with an invalid label
        string memory invalidLabel = "invalid";
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint256 roleBitmap = TestUtils.ALL_ROLES;
        bytes memory ejectionData = _createEjectionData(invalidLabel, l1Owner, l1Subregistry, l1Resolver, expiryTime, roleBitmap);
        
        // Make sure user still owns the token
        assertEq(ethRegistry.ownerOf(tokenId), user);
        
        // User transfers the token to the bridge controller, should revert with InvalidLabel
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(EjectionController.InvalidLabel.selector, tokenId, invalidLabel));
        ethRegistry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);
    }

    function test_Revert_onERC1155Received_UnauthorizedCaller() public {
        // Prepare valid data for ejection
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint256 roleBitmap = TestUtils.ALL_ROLES;
        bytes memory ejectionData = _createEjectionData(testLabel, l1Owner, l1Subregistry, l1Resolver, expiryTime, roleBitmap);
        
        // Try to call onERC1155Received directly (not through registry)
        vm.expectRevert(abi.encodeWithSelector(EjectionController.UnauthorizedCaller.selector, address(this)));
        controller.onERC1155Received(address(this), user, tokenId, 1, ejectionData);
    }

    function test_tokenObserver_callbacks() public {
        // First eject the name so the controller owns it and becomes the observer
        uint64 expiryTime = uint64(block.timestamp + expiryDuration);
        uint32 roleBitmap = uint32(TestUtils.ALL_ROLES);
        bytes memory ejectionData = _createEjectionData(testLabel, l1Owner, l1Subregistry, l1Resolver, expiryTime, roleBitmap);
        vm.prank(user);
        ethRegistry.safeTransferFrom(user, address(controller), tokenId, 1, ejectionData);
        
        // Verify controller owns the token and is the observer
        assertEq(ethRegistry.ownerOf(tokenId), address(controller), "Controller should own the token");
        assertEq(address(ethRegistry.tokenObservers(tokenId)), address(controller), "Controller should be the observer");
        
        // Reset tracking flags
        controller.resetTracking();
        
        // Test onRenew callback
        uint64 newExpiry = uint64(block.timestamp + expiryDuration * 2);
        address renewer = address(this);
        controller.onRenew(tokenId, newExpiry, renewer);
        assertTrue(controller.onRenewCalled(), "onRenew should call _onRenew");
        
        // Test onRelinquish callback
        address relinquisher = address(this);
        controller.onRelinquish(tokenId, relinquisher);
        assertTrue(controller.onRelinquishCalled(), "onRelinquish should call _onRelinquish");
    }
} 