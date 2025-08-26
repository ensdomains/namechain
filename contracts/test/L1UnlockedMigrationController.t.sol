// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {MockBaseRegistrar} from "../src/mocks/v1/MockBaseRegistrar.sol";
import {INameWrapper, CANNOT_UNWRAP} from "@ens/contracts/wrapper/INameWrapper.sol";
import {L1UnlockedMigrationController} from "../src/L1/L1UnlockedMigrationController.sol";
import {TransferData, MigrationData} from "../src/common/TransferData.sol";
import {MockL1Bridge} from "../src/mocks/MockL1Bridge.sol";
import {IBridge, BridgeMessageType, LibBridgeRoles} from "../src/common/IBridge.sol";
import {BridgeEncoder} from "../src/common/BridgeEncoder.sol";
import {L1BridgeController} from "../src/L1/L1BridgeController.sol";
import {IPermissionedRegistry} from "../src/common/IPermissionedRegistry.sol";
import {RegistryDatastore} from "../src/common/RegistryDatastore.sol";
import {PermissionedRegistry} from "../src/common/PermissionedRegistry.sol";
import {IRegistryMetadata} from "../src/common/IRegistryMetadata.sol";
import {LibEACBaseRoles} from "../src/common/EnhancedAccessControl.sol";
import {LibRegistryRoles} from "../src/common/LibRegistryRoles.sol";
import {NameUtils} from "../src/common/NameUtils.sol";

// Simple mock that implements IRegistryMetadata
contract MockRegistryMetadata is IRegistryMetadata {
    function tokenUri(uint256) external pure override returns (string memory) {
        return "";
    }
}

// Mock ERC1155 contract for wrapped names
contract MockNameWrapper is ERC1155 {
    mapping(uint256 => address) private _tokenOwners;
    mapping(uint256 => uint32) private _tokenFuses;
    
    constructor() ERC1155("https://metadata.ens.domains/") {}

    function wrapETH2LD(string memory label, address owner, uint16, address) external {
        uint256 tokenId = uint256(keccak256(bytes(label)));
        _mint(owner, tokenId, 1, "");
        _tokenOwners[tokenId] = owner;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        return _tokenOwners[tokenId];
    }

    function getData(uint256 tokenId) external view returns (address, uint32, uint64) {
        return (_tokenOwners[tokenId], _tokenFuses[tokenId], 0);
    }

    function setFuses(uint256 tokenId, uint32 fuses) external {
        _tokenFuses[tokenId] = fuses;
    }
    
    
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public override {
        super.safeTransferFrom(from, to, id, amount, data);
        _tokenOwners[id] = to;
    }
    
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public override {
        super.safeBatchTransferFrom(from, to, ids, amounts, data);
        for (uint256 i = 0; i < ids.length; i++) {
            _tokenOwners[ids[i]] = to;
        }
    }

    function unwrapETH2LD(bytes32 label, address newRegistrant, address /*newController*/) external {
        uint256 tokenId = uint256(label);
        // Mock unwrap by burning the ERC1155 token from the caller (migration controller)
        _burn(msg.sender, tokenId, 1);
        _tokenOwners[tokenId] = newRegistrant;
    }
}

contract TestL1UnlockedMigrationController is Test, ERC1155Holder, ERC721Holder {
    MockBaseRegistrar ethRegistryV1;
    MockNameWrapper nameWrapper;
    L1UnlockedMigrationController migrationController;
    MockL1Bridge mockBridge;
    
    // Real components for testing
    L1BridgeController realL1BridgeController;
    RegistryDatastore datastore;
    PermissionedRegistry registry;
    MockRegistryMetadata registryMetadata;

    address user = address(0x1234);
    address controller = address(0x5678);
    
    string testLabel = "test";
    uint256 testTokenId;

    /**
     * Helper method to create properly encoded migration data for transfers
     */
    function _createMigrationData(string memory label) internal pure returns (MigrationData memory) {
        return MigrationData({
            transferData: TransferData({
                label: label,
                owner: address(0),
                subregistry: address(0),
                resolver: address(0),
                roleBitmap: 0,
                expires: 0
            }),
            toL1: false,
            dnsEncodedName: "",
            salt: ""
        });
    }

    /**
     * Helper method to create properly encoded migration data with toL1 flag
     */
    function _createMigrationDataWithL1Flag(string memory label, bool toL1) internal view returns (MigrationData memory) {
        return MigrationData({
            transferData: TransferData({
                label: label,
                owner: address(0x1111),
                subregistry: address(0x2222),
                resolver: address(0x3333),
                roleBitmap: 0,
                expires: uint64(block.timestamp + 86400) // Valid future expiration
            }),
            toL1: toL1,
            dnsEncodedName: "",
            salt: ""
        });
    }

    /**
     * Helper method to verify that a NameBridgedToL2 event was emitted with correct data
     */
    function _assertBridgeMigrationEvent(string memory expectedLabel) internal {
        Vm.Log[] memory entries = vm.getRecordedLogs();
        _assertBridgeMigrationEventWithLogs(expectedLabel, entries);
    }

    /**
     * Helper method to verify that a NameBridgedToL2 event was emitted with correct data using provided logs
     */
    function _assertBridgeMigrationEventWithLogs(string memory expectedLabel, Vm.Log[] memory entries) internal view {
        bool foundMigrationEvent = false;
        bytes32 expectedSig = keccak256("NameBridgedToL2(bytes)");
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].emitter == address(mockBridge) && entries[i].topics[0] == expectedSig) {
                // For NameBridgedToL2(bytes message) - single parameter is NOT indexed
                // so the message is in the data field
                (bytes memory message) = abi.decode(entries[i].data, (bytes));
                // Decode the ejection message to get the transfer data
                (, TransferData memory decodedTransferData) = BridgeEncoder.decodeEjection(message);
                if (keccak256(bytes(decodedTransferData.label)) == keccak256(bytes(expectedLabel))) {
                    foundMigrationEvent = true;
                    break;  
                }
            }
        }
        assertTrue(foundMigrationEvent, string(abi.encodePacked("NameBridgedToL2 event not found for token: ", expectedLabel)));
    }

    /**
     * Helper method to count NameBridgedToL2 events for multiple tokens
     */
    function _countBridgeMigrationEvents(uint256[] memory expectedTokenIds) internal returns (uint256) {
        Vm.Log[] memory entries = vm.getRecordedLogs();
        return _countBridgeMigrationEventsWithLogs(expectedTokenIds, entries);
    }

    /**
     * Helper method to count NameBridgedToL2 events for multiple tokens using provided logs
     */
    function _countBridgeMigrationEventsWithLogs(uint256[] memory expectedTokenIds, Vm.Log[] memory entries) internal view returns (uint256) {
        uint256 migratedEventCount = 0;
        bytes32 expectedSig = keccak256("NameBridgedToL2(bytes)");

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].emitter == address(mockBridge) && entries[i].topics[0] == expectedSig) {
                // For NameBridgedToL2(bytes message) - single parameter is NOT indexed
                // so the message is in the data field
                (bytes memory message) = abi.decode(entries[i].data, (bytes));
                // Decode the ejection message to get the transfer data
                (, TransferData memory decodedTransferData) = BridgeEncoder.decodeEjection(message);
                uint256 emittedTokenId = uint256(keccak256(bytes(decodedTransferData.label)));
                
                // Check if this tokenId is in our expected list
                for (uint256 j = 0; j < expectedTokenIds.length; j++) {
                    if (emittedTokenId == expectedTokenIds[j]) {
                        migratedEventCount++;
                        break;
                    }
                }
            }
        }
        return migratedEventCount;
    }

    /**
     * Helper method to verify that a NameEjectedToL1 event was emitted
     */
    function _assertL1MigratorEvent(string memory expectedLabel, Vm.Log[] memory entries) internal view {
        bool foundMigratorEvent = false;
        bytes32 expectedSig = keccak256("NameEjectedToL1(bytes,uint256)");
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].emitter == address(realL1BridgeController) && entries[i].topics[0] == expectedSig) {
                // NameEjectedToL1(bytes dnsEncodedName, uint256 tokenId)
                (bytes memory dnsEncodedName, ) = abi.decode(entries[i].data, (bytes, uint256));
                // Extract label from DNS encoded name (first byte is length, then the label)
                uint8 labelLength = uint8(dnsEncodedName[0]);
                bytes memory labelBytes = new bytes(labelLength);
                for (uint256 j = 0; j < labelLength; j++) {
                    labelBytes[j] = dnsEncodedName[j + 1];
                }
                string memory emittedLabel = string(labelBytes);
                if (keccak256(bytes(emittedLabel)) == keccak256(bytes(expectedLabel))) {
                    foundMigratorEvent = true;
                    break;
                }
            }
        }
        assertTrue(foundMigratorEvent, string(abi.encodePacked("NameEjectedToL1 event not found for label: ", expectedLabel)));
    }

    function setUp() public {
        // Set up real registry infrastructure
        datastore = new RegistryDatastore();
        registryMetadata = new MockRegistryMetadata();
        
        // Deploy the real registry
        registry = new PermissionedRegistry(datastore, registryMetadata, address(this), LibEACBaseRoles.ALL_ROLES);
        
        // Deploy mock base registrar and name wrapper (keep these as mocks)
        ethRegistryV1 = new MockBaseRegistrar();
        ethRegistryV1.addController(controller);
        nameWrapper = new MockNameWrapper();

        // Deploy mock bridge
        mockBridge = new MockL1Bridge();
        
        // Deploy REAL L1BridgeController with real dependencies
        realL1BridgeController = new L1BridgeController(registry, mockBridge, registry);
        
        // Grant necessary roles to the ejection controller
        registry.grantRootRoles(
            LibRegistryRoles.ROLE_REGISTRAR | LibRegistryRoles.ROLE_RENEW | LibRegistryRoles.ROLE_BURN, 
            address(realL1BridgeController)
        );
        
        // Deploy migration controller with the REAL ejection controller
        migrationController = new L1UnlockedMigrationController(
            ethRegistryV1, 
            INameWrapper(address(nameWrapper)), 
            mockBridge, 
            realL1BridgeController
        );
        
        // Grant ROLE_EJECTOR to the migration controller so it can call the ejection controller
        realL1BridgeController.grantRootRoles(LibBridgeRoles.ROLE_EJECTOR, address(migrationController));
        
        testTokenId = uint256(keccak256(bytes(testLabel)));
    }

    function test_constructor() public view {
        assertEq(address(migrationController.ethRegistryV1()), address(ethRegistryV1));
        assertEq(address(migrationController.nameWrapper()), address(nameWrapper));
        assertEq(address(migrationController.bridge()), address(mockBridge));
        assertEq(address(migrationController.l1BridgeController()), address(realL1BridgeController));
        assertEq(migrationController.owner(), address(this));
    }

    function test_migrateUnwrappedEthName() public {
        // Register a name in the v1 registrar
        vm.prank(controller);
        ethRegistryV1.register(testTokenId, user, 86400);
        
        // Verify user owns the token
        assertEq(ethRegistryV1.ownerOf(testTokenId), user);
        
        // Create migration data
        MigrationData memory migrationData = _createMigrationData(testLabel);
        bytes memory data = abi.encode(migrationData);
        
        vm.recordLogs();
        
        // Transfer to migration controller (simulating migration)
        vm.prank(user);
        ethRegistryV1.safeTransferFrom(user, address(migrationController), testTokenId, data);
        
        // Verify the migration controller now owns the token
        assertEq(ethRegistryV1.ownerOf(testTokenId), address(migrationController));
        
        // Get logs for assertions
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        // Check for migration event from the bridge (toL1=false by default)
        _assertBridgeMigrationEventWithLogs(testLabel, entries);
        
        // Verify NO L1 ejection controller events when toL1=false
        uint256 l1MigratorEventCount = 0;
        bytes32 expectedSig = keccak256("NameEjectedToL1(bytes,uint256)");
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].emitter == address(realL1BridgeController) && entries[i].topics[0] == expectedSig) {
                l1MigratorEventCount++;
            }
        }
        assertEq(l1MigratorEventCount, 0, "Should have no L1 migrator events when toL1=false");
    }

    function test_migrateUnwrappedEthName_toL1() public {
        // Register a name in the v1 registrar
        vm.prank(controller);
        ethRegistryV1.register(testTokenId, user, 86400);
        
        // Verify user owns the token
        assertEq(ethRegistryV1.ownerOf(testTokenId), user);
        
        // Create migration data with toL1 flag set to true
        MigrationData memory migrationData = _createMigrationDataWithL1Flag(testLabel, true);
        bytes memory data = abi.encode(migrationData);
        
        vm.recordLogs();
        
        // Transfer to migration controller (simulating migration)
        vm.prank(user);
        ethRegistryV1.safeTransferFrom(user, address(migrationController), testTokenId, data);
        
        // Verify the migration controller now owns the token
        assertEq(ethRegistryV1.ownerOf(testTokenId), address(migrationController));
        
        // Get logs once and use for assertions
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        // When toL1=true, should NOT send to bridge
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = testTokenId;
        uint256 bridgeEventCount = _countBridgeMigrationEventsWithLogs(tokenIds, entries);
        assertEq(bridgeEventCount, 0, "Should not send to bridge when toL1=true");
        
        // Should only call L1 ejection controller
        _assertL1MigratorEvent(testLabel, entries);
    }

    function test_Revert_migrateUnwrappedEthName_wrong_caller() public {
        // Register a name in the v1 registrar
        vm.prank(controller);
        ethRegistryV1.register(testTokenId, user, 86400);
        
        // Create migration data
        MigrationData memory migrationData = _createMigrationData(testLabel);
        bytes memory data = abi.encode(migrationData);
        
        // Try to transfer from wrong registry
        vm.expectRevert(abi.encodeWithSelector(L1UnlockedMigrationController.UnauthorizedCaller.selector, address(this)));
        migrationController.onERC721Received(address(this), user, testTokenId, data);
    }

    function test_Revert_migrateUnwrappedEthName_not_owner() public {
        // Register a name in the v1 registrar
        vm.prank(controller);
        ethRegistryV1.register(testTokenId, user, 86400);
        
        // Create migration data
        MigrationData memory migrationData = _createMigrationData(testLabel);
        bytes memory data = abi.encode(migrationData);
        
        // Try to call onERC721Received directly when migration controller doesn't own the token
        // This should fail with UnauthorizedCaller because we're calling it directly
        // and msg.sender is not ethRegistryV1
        vm.expectRevert(abi.encodeWithSelector(L1UnlockedMigrationController.UnauthorizedCaller.selector, address(this)));
        migrationController.onERC721Received(address(this), user, testTokenId, data);
    }

    function test_migrateUnlockedWrappedEthName_single() public {
        // Wrap a name (simulate) - this should mint the token to the user
        nameWrapper.wrapETH2LD(testLabel, user, 0, address(0));
        // Ensure fuses are 0 (unlocked)
        nameWrapper.setFuses(testTokenId, 0);
        
        // Verify user owns the wrapped token
        assertEq(nameWrapper.balanceOf(user, testTokenId), 1);
        
        // Create migration data
        MigrationData memory migrationData = _createMigrationData(testLabel);
        bytes memory data = abi.encode(migrationData);
        
        vm.recordLogs();
        
        // Transfer wrapped token to migration controller
        vm.prank(user);
        nameWrapper.safeTransferFrom(user, address(migrationController), testTokenId, 1, data);
        
        // Get logs for assertions
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        // Check for migration event from the bridge (toL1=false by default)
        _assertBridgeMigrationEventWithLogs(testLabel, entries);
        
        // Verify NO L1 ejection controller events when toL1=false
        uint256 l1MigratorEventCount = 0;
        bytes32 expectedSig = keccak256("NameEjectedToL1(bytes,uint256)");
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].emitter == address(realL1BridgeController) && entries[i].topics[0] == expectedSig) {
                l1MigratorEventCount++;
            }
        }
        assertEq(l1MigratorEventCount, 0, "Should have no L1 migrator events when toL1=false");
    }

    function test_migrateUnlockedWrappedEthName_single_toL1() public {
        // Wrap a name (simulate) - this should mint the token to the user
        nameWrapper.wrapETH2LD(testLabel, user, 0, address(0));
        // Ensure fuses are 0 (unlocked)
        nameWrapper.setFuses(testTokenId, 0);
        
        // Verify user owns the wrapped token
        assertEq(nameWrapper.balanceOf(user, testTokenId), 1);
        
        // Create migration data with toL1 flag set to true
        MigrationData memory migrationData = _createMigrationDataWithL1Flag(testLabel, true);
        bytes memory data = abi.encode(migrationData);
        
        vm.recordLogs();
        
        // Transfer wrapped token to migration controller
        vm.prank(user);
        nameWrapper.safeTransferFrom(user, address(migrationController), testTokenId, 1, data);
        
        // Get logs once and use for assertions
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        // When toL1=true, should NOT send to bridge
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = testTokenId;
        uint256 bridgeEventCount = _countBridgeMigrationEventsWithLogs(tokenIds, entries);
        assertEq(bridgeEventCount, 0, "Should not send to bridge when toL1=true");
        
        // Should only call L1 ejection controller
        _assertL1MigratorEvent(testLabel, entries);
    }

    function test_migrateWrappedEthName_batch_allUnlocked() public {
        string memory label1 = "unlocked1";
        string memory label2 = "unlocked2";
        uint256 tokenId1 = uint256(keccak256(bytes(label1)));
        uint256 tokenId2 = uint256(keccak256(bytes(label2)));

        nameWrapper.wrapETH2LD(label1, user, 0, address(0));
        nameWrapper.setFuses(tokenId1, 0); // Unlocked
        nameWrapper.wrapETH2LD(label2, user, 0, address(0));
        nameWrapper.setFuses(tokenId2, 0); // Unlocked
        
        // Verify user owns the wrapped tokens
        assertEq(nameWrapper.balanceOf(user, tokenId1), 1);
        assertEq(nameWrapper.balanceOf(user, tokenId2), 1);
        
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;
        
        MigrationData[] memory migrationDataArray = new MigrationData[](2);
        migrationDataArray[0] = _createMigrationData(label1);
        migrationDataArray[1] = _createMigrationData(label2);
        
        bytes memory data = abi.encode(migrationDataArray);
        
        vm.recordLogs();
        
        vm.prank(user);
        nameWrapper.safeBatchTransferFrom(user, address(migrationController), tokenIds, amounts, data);
        
        // Get logs for assertions
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        // Check that both names were migrated to L2 (toL1=false by default)
        uint256 migratedEventCount = _countBridgeMigrationEventsWithLogs(tokenIds, entries);
        assertEq(migratedEventCount, 2, "Both names should go to bridge when toL1=false");
        
        // Verify NO L1 ejection controller events when toL1=false
        uint256 l1MigratorEventCount = 0;
        bytes32 expectedSig = keccak256("NameEjectedToL1(bytes,uint256)");
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].emitter == address(realL1BridgeController) && entries[i].topics[0] == expectedSig) {
                l1MigratorEventCount++;
            }
        }
        assertEq(l1MigratorEventCount, 0, "Should have no L1 migrator events when toL1=false");
    }

    function test_migrateWrappedEthName_batch_mixedL1Flags() public {
        string memory label1 = "toL2Only";
        string memory label2 = "toL1AndL2";
        uint256 tokenId1 = uint256(keccak256(bytes(label1)));
        uint256 tokenId2 = uint256(keccak256(bytes(label2)));

        nameWrapper.wrapETH2LD(label1, user, 0, address(0));
        nameWrapper.setFuses(tokenId1, 0); // Unlocked
        nameWrapper.wrapETH2LD(label2, user, 0, address(0));
        nameWrapper.setFuses(tokenId2, 0); // Unlocked
        
        // Verify user owns the wrapped tokens
        assertEq(nameWrapper.balanceOf(user, tokenId1), 1);
        assertEq(nameWrapper.balanceOf(user, tokenId2), 1);
        
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;
        
        MigrationData[] memory migrationDataArray = new MigrationData[](2);
        migrationDataArray[0] = _createMigrationDataWithL1Flag(label1, false); // Only to L2
        migrationDataArray[1] = _createMigrationDataWithL1Flag(label2, true);  // Only to L1
        
        bytes memory data = abi.encode(migrationDataArray);
        
        vm.recordLogs();
        
        vm.prank(user);
        nameWrapper.safeBatchTransferFrom(user, address(migrationController), tokenIds, amounts, data);
        
        // Get logs once and use for all assertions
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        // Check that only the first name (toL1=false) was migrated to L2
        uint256[] memory l2TokenIds = new uint256[](1);
        l2TokenIds[0] = tokenId1;
        uint256 migratedEventCount = _countBridgeMigrationEventsWithLogs(l2TokenIds, entries);
        assertEq(migratedEventCount, 1, "Only the toL1=false name should go to bridge");
        
        // Check that only the second name (toL1=true) was migrated to L1
        _assertL1MigratorEvent(label2, entries);
        
        // Verify the first name was NOT migrated to L1 by checking event count
        uint256 l1MigratorEventCount = 0;
        bytes32 expectedSig = keccak256("NameEjectedToL1(bytes,uint256)");
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].emitter == address(realL1BridgeController) && entries[i].topics[0] == expectedSig) {
                l1MigratorEventCount++;
            }
        }
        assertEq(l1MigratorEventCount, 1, "Should have exactly 1 L1 migrator event");
    }



    function test_Revert_migrateWrappedEthName_single_locked() public {
        // First wrap a name so the user actually owns it
        vm.prank(user);
        nameWrapper.wrapETH2LD(testLabel, user, 0, address(0));
        nameWrapper.setFuses(testTokenId, CANNOT_UNWRAP); // Mark as locked
        
        // Create migration data
        MigrationData memory migrationData = _createMigrationData(testLabel);
        bytes memory data = abi.encode(migrationData);
        
        // Try to transfer locked name (should revert with MigrationNotSupported)
        vm.expectRevert(abi.encodeWithSelector(L1UnlockedMigrationController.MigrationNotSupported.selector));
        vm.prank(user);
        nameWrapper.safeTransferFrom(user, address(migrationController), testTokenId, 1, data);
    }

    function test_Revert_migrateWrappedEthName_batch_locked() public {
        
        string memory label1 = "locked1";
        string memory label2 = "locked2";
        uint256 tokenId1 = uint256(keccak256(bytes(label1)));
        uint256 tokenId2 = uint256(keccak256(bytes(label2)));
        
        // First wrap names so the user actually owns them
        vm.startPrank(user);
        nameWrapper.wrapETH2LD(label1, user, 0, address(0));
        nameWrapper.setFuses(tokenId1, CANNOT_UNWRAP); // Mark as locked
        nameWrapper.wrapETH2LD(label2, user, 0, address(0));
        nameWrapper.setFuses(tokenId2, CANNOT_UNWRAP); // Mark as locked
        vm.stopPrank();
        
        // Prepare batch data
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;
        
        MigrationData[] memory migrationDataArray = new MigrationData[](2);
        migrationDataArray[0] = _createMigrationData(label1);
        migrationDataArray[1] = _createMigrationData(label2);
        
        bytes memory data = abi.encode(migrationDataArray);
        
        // Should revert when processing the first locked name
        vm.expectRevert(abi.encodeWithSelector(L1UnlockedMigrationController.MigrationNotSupported.selector));
        vm.prank(user);
        nameWrapper.safeBatchTransferFrom(user, address(migrationController), tokenIds, amounts, data);
    }

    function test_supportsInterface() public view {
        assertTrue(migrationController.supportsInterface(type(IERC165).interfaceId));
        assertTrue(migrationController.supportsInterface(type(IERC721Receiver).interfaceId));
        assertTrue(migrationController.supportsInterface(type(IERC1155Receiver).interfaceId));
        // Ownable is not directly advertised via supportsInterface in L1UnlockedMigrationController based on its ERC165 logic
        // assertTrue(migrationController.supportsInterface(type(Ownable).interfaceId)); 
    }

    function test_Revert_onERC1155Received_wrong_caller() public {
        // Create migration data
        MigrationData memory migrationData = _createMigrationData(testLabel);
        bytes memory data = abi.encode(migrationData);
        
        // Try to call onERC1155Received from wrong contract (not nameWrapper)
        vm.expectRevert(abi.encodeWithSelector(L1UnlockedMigrationController.UnauthorizedCaller.selector, address(this)));
        migrationController.onERC1155Received(address(this), user, testTokenId, 1, data);
    }

    function test_Revert_onERC1155BatchReceived_wrong_caller() public {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = testTokenId;
        
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;
        
        // For batch, data is MigrationData[]
        MigrationData[] memory migrationDataArray = new MigrationData[](1);
        migrationDataArray[0] = _createMigrationData(testLabel);
        
        bytes memory data = abi.encode(migrationDataArray);
        
        // Try to call onERC1155BatchReceived from wrong contract (not nameWrapper)
        vm.expectRevert(abi.encodeWithSelector(L1UnlockedMigrationController.UnauthorizedCaller.selector, address(this)));
        migrationController.onERC1155BatchReceived(address(this), user, tokenIds, amounts, data);
    }

    function test_onERC1155Received_nameWrapper_authorization() public {
        // Create migration data (single item)
        MigrationData memory migrationData = _createMigrationData(testLabel);
        bytes memory data = abi.encode(migrationData); // onERC1155Received expects a single MigrationData
        
        // Call onERC1155Received as nameWrapper (should work)
        // Use a locked token so it doesn't try to unwrap (which would trigger the ERC1155InvalidReceiver issue)
        nameWrapper.setFuses(testTokenId, CANNOT_UNWRAP); // Mark as locked
        
        vm.expectRevert(abi.encodeWithSelector(L1UnlockedMigrationController.MigrationNotSupported.selector));
        vm.prank(address(nameWrapper));
        migrationController.onERC1155Received(address(this), user, testTokenId, 1, data);
    }

    function test_onERC1155BatchReceived_nameWrapper_authorization() public {
        string memory label1 = "batchAuth1";
        uint256 tokenId1 = uint256(keccak256(bytes(label1)));

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId1;
        
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;
        
        MigrationData[] memory migrationDataArray = new MigrationData[](1);
        migrationDataArray[0] = _createMigrationData(label1);
        
        bytes memory data = abi.encode(migrationDataArray); // onERC1155BatchReceived expects MigrationData[]
        
        // Call onERC1155BatchReceived as nameWrapper (should work)
        // Use a locked token so it doesn't try to unwrap (which would trigger the ERC1155InvalidReceiver issue)
        nameWrapper.setFuses(tokenId1, CANNOT_UNWRAP); // Mark as locked
        
        vm.expectRevert(abi.encodeWithSelector(L1UnlockedMigrationController.MigrationNotSupported.selector));
        vm.prank(address(nameWrapper));
        migrationController.onERC1155BatchReceived(address(this), user, tokenIds, amounts, data);
    }

    function test_Revert_migrateUnwrappedEthName_tokenId_mismatch() public {
        // Register a name in the v1 registrar
        vm.prank(controller);
        ethRegistryV1.register(testTokenId, user, 86400);
        
        // Create migration data with wrong label
        MigrationData memory migrationData = _createMigrationData("wronglabel");
        bytes memory data = abi.encode(migrationData);
        
        // Calculate expected tokenId for the wrong label
        uint256 expectedTokenId = uint256(keccak256(bytes("wronglabel")));
        
        // Try to transfer with mismatched tokenId and label
        vm.expectRevert(abi.encodeWithSelector(L1UnlockedMigrationController.TokenIdMismatch.selector, testTokenId, expectedTokenId));
        vm.prank(user);
        ethRegistryV1.safeTransferFrom(user, address(migrationController), testTokenId, data);
    }

    function test_Revert_migrateWrappedEthName_tokenId_mismatch() public {
        // Wrap a name (simulate) - this should mint the token to the user
        nameWrapper.wrapETH2LD(testLabel, user, 0, address(0));
        
        // Verify user owns the wrapped token
        assertEq(nameWrapper.balanceOf(user, testTokenId), 1);
        
        // Create migration data with wrong label
        MigrationData memory migrationData = _createMigrationData("wronglabel");
        bytes memory data = abi.encode(migrationData);
        
        // Calculate expected tokenId for the wrong label
        uint256 expectedTokenId = uint256(keccak256(bytes("wronglabel")));
        
        // Try to transfer with mismatched tokenId and label
        vm.expectRevert(abi.encodeWithSelector(L1UnlockedMigrationController.TokenIdMismatch.selector, testTokenId, expectedTokenId));
        vm.prank(user);
        nameWrapper.safeTransferFrom(user, address(migrationController), testTokenId, 1, data);
    }

    function test_Revert_migrateWrappedEthName_batch_tokenId_mismatch() public {
        string memory label1 = "correct1";
        string memory wrongLabel2 = "wrong2";
        uint256 tokenId1 = uint256(keccak256(bytes(label1)));
        uint256 tokenId2 = uint256(keccak256(bytes("correct2"))); // This is the correct tokenId
        
        nameWrapper.wrapETH2LD(label1, user, 0, address(0));
        nameWrapper.wrapETH2LD("correct2", user, 0, address(0));
        
        // Verify user owns the wrapped tokens
        assertEq(nameWrapper.balanceOf(user, tokenId1), 1);
        assertEq(nameWrapper.balanceOf(user, tokenId2), 1);
        
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;
        
        // Create migration data with one wrong label
        MigrationData[] memory migrationDataArray = new MigrationData[](2);
        migrationDataArray[0] = _createMigrationData(label1); // correct
        migrationDataArray[1] = _createMigrationData(wrongLabel2); // wrong label for tokenId2
        
        bytes memory data = abi.encode(migrationDataArray);
        
        // Calculate expected tokenId for the wrong label
        uint256 expectedTokenId = uint256(keccak256(bytes(wrongLabel2)));
        
        // Should revert when processing the second token with mismatched data
        vm.expectRevert(abi.encodeWithSelector(L1UnlockedMigrationController.TokenIdMismatch.selector, tokenId2, expectedTokenId));
        vm.prank(user);
        nameWrapper.safeBatchTransferFrom(user, address(migrationController), tokenIds, amounts, data);
    }

} 