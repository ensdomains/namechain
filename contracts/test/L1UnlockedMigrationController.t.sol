// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IBaseRegistrar} from "@ens/contracts/ethregistrar/IBaseRegistrar.sol";
import {INameWrapper, CANNOT_UNWRAP} from "@ens/contracts/wrapper/INameWrapper.sol";
import {L1UnlockedMigrationController} from "../src/L1/L1UnlockedMigrationController.sol";
import {TransferData, MigrationData} from "../src/common/TransferData.sol";
import {MockL1Bridge} from "../src/mocks/MockL1Bridge.sol";
import {IBridge, BridgeMessageType, BridgeEncoder} from "../src/common/IBridge.sol";
import {IL1Migrator} from "../src/L1/IL1Migrator.sol";

// Simple mock that implements IBaseRegistrar without the compilation issues
contract MockBaseRegistrar is ERC721, IBaseRegistrar {
    mapping(address => bool) public controllers;
    mapping(uint256 => uint256) public expiries;
    uint256 public constant GRACE_PERIOD = 90 days;

    constructor() ERC721("MockETHRegistrar", "METH") {}

    function addController(address controller) external override {
        controllers[controller] = true;
        emit ControllerAdded(controller);
    }

    function removeController(address controller) external override {
        controllers[controller] = false;
        emit ControllerRemoved(controller);
    }

    function setResolver(address) external override {
        // Mock implementation
    }

    function nameExpires(uint256 id) external view override returns (uint256) {
        return expiries[id];
    }

    function available(uint256 id) public view override returns (bool) {
        return expiries[id] + GRACE_PERIOD < block.timestamp || expiries[id] == 0;
    }

    function register(uint256 id, address owner, uint256 duration) external override returns (uint256) {
        require(controllers[msg.sender], "Not a controller");
        require(available(id), "Name not available");
        
        expiries[id] = block.timestamp + duration;
        if (_ownerOf(id) != address(0)) {
            _burn(id);
        }
        _mint(owner, id);
        
        emit NameRegistered(id, owner, block.timestamp + duration);
        return block.timestamp + duration;
    }

    function renew(uint256 id, uint256 duration) external override returns (uint256) {
        require(controllers[msg.sender], "Not a controller");
        require(expiries[id] + GRACE_PERIOD >= block.timestamp, "Name expired");
        
        expiries[id] += duration;
        emit NameRenewed(id, expiries[id]);
        return expiries[id];
    }

    function reclaim(uint256 id, address /*owner*/) external override view {
        require(ownerOf(id) == msg.sender, "Not owner");
        // Mock implementation
    }

    function ownerOf(uint256 tokenId) public view override(ERC721, IERC721) returns (address) {
        require(expiries[tokenId] > block.timestamp, "Name expired");
        return super.ownerOf(tokenId);
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
    
    function unwrap(bytes32 /*node*/, bytes32 label, address owner) external {
        uint256 tokenId = uint256(label);
        // Mock unwrap by burning the ERC1155 token from the caller (migration controller)
        // This is a simplified mock implementation
        _burn(msg.sender, tokenId, 1);
        _tokenOwners[tokenId] = owner;
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
}

contract MockL1Migrator is IL1Migrator {
    event MockMigrateFromV1Called(TransferData transferData);

    function migrateFromV1(TransferData memory transferData) external {
        emit MockMigrateFromV1Called(transferData);
    }
}

contract TestL1UnlockedMigrationController is Test, ERC1155Holder, ERC721Holder {
    MockBaseRegistrar ethRegistryV1;
    MockNameWrapper nameWrapper;
    L1UnlockedMigrationController migrationController;
    MockL1Bridge mockBridge;
    MockL1Migrator mockL1Migrator;

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
            data: ""
        });
    }

    /**
     * Helper method to create properly encoded migration data with toL1 flag
     */
    function _createMigrationDataWithL1Flag(string memory label, bool toL1) internal pure returns (MigrationData memory) {
        return MigrationData({
            transferData: TransferData({
                label: label,
                owner: address(0),
                subregistry: address(0),
                resolver: address(0),
                roleBitmap: 0,
                expires: 0
            }),
            toL1: toL1,
            data: ""
        });
    }

    /**
     * Helper method to verify that a NameMigratedToL2 event was emitted with correct data
     */
    function _assertBridgeMigrationEvent(string memory expectedLabel) internal {
        Vm.Log[] memory entries = vm.getRecordedLogs();
        _assertBridgeMigrationEventWithLogs(expectedLabel, entries);
    }

    /**
     * Helper method to verify that a NameMigratedToL2 event was emitted with correct data using provided logs
     */
    function _assertBridgeMigrationEventWithLogs(string memory expectedLabel, Vm.Log[] memory entries) internal view {
        bool foundMigrationEvent = false;
        bytes32 expectedSig = keccak256("NameMigratedToL2(bytes,bytes)");
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].emitter == address(mockBridge) && entries[i].topics[0] == expectedSig) {
                // For NameMigratedToL2(bytes indexed dnsEncodedName, bytes data)
                // topics[1] contains the dnsEncodedName hash
                // data contains the migration data bytes
                bytes memory migrationDataBytes = abi.decode(entries[i].data, (bytes));
                MigrationData memory decodedMigrationData = abi.decode(migrationDataBytes, (MigrationData));
                if (keccak256(bytes(decodedMigrationData.transferData.label)) == keccak256(bytes(expectedLabel))) {
                    foundMigrationEvent = true;
                    break;  
                }
            }
        }
        assertTrue(foundMigrationEvent, string(abi.encodePacked("NameMigratedToL2 event not found for token: ", expectedLabel)));
    }

    /**
     * Helper method to count NameMigratedToL2 events for multiple tokens
     */
    function _countBridgeMigrationEvents(uint256[] memory expectedTokenIds) internal returns (uint256) {
        Vm.Log[] memory entries = vm.getRecordedLogs();
        return _countBridgeMigrationEventsWithLogs(expectedTokenIds, entries);
    }

    /**
     * Helper method to count NameMigratedToL2 events for multiple tokens using provided logs
     */
    function _countBridgeMigrationEventsWithLogs(uint256[] memory expectedTokenIds, Vm.Log[] memory entries) internal view returns (uint256) {
        uint256 migratedEventCount = 0;
        bytes32 expectedSig = keccak256("NameMigratedToL2(bytes,bytes)");

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].emitter == address(mockBridge) && entries[i].topics[0] == expectedSig) {
                // For NameMigratedToL2(bytes indexed dnsEncodedName, bytes data)
                // we need to decode the migration data to get the label and compute the tokenId
                bytes memory migrationDataBytes = abi.decode(entries[i].data, (bytes));
                MigrationData memory decodedMigrationData = abi.decode(migrationDataBytes, (MigrationData));
                uint256 emittedTokenId = uint256(keccak256(bytes(decodedMigrationData.transferData.label)));
                
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
     * Helper method to verify that a MockMigrateFromV1Called event was emitted
     */
    function _assertL1MigratorEvent(string memory expectedLabel, Vm.Log[] memory entries) internal view {
        bool foundMigratorEvent = false;
        bytes32 expectedSig = keccak256("MockMigrateFromV1Called((string,address,address,address,uint256,uint64))");
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].emitter == address(mockL1Migrator) && entries[i].topics[0] == expectedSig) {
                TransferData memory decodedTransferData = abi.decode(entries[i].data, (TransferData));
                if (keccak256(bytes(decodedTransferData.label)) == keccak256(bytes(expectedLabel))) {
                    foundMigratorEvent = true;
                    break;
                }
            }
        }
        assertTrue(foundMigratorEvent, string(abi.encodePacked("MockMigrateFromV1Called event not found for label: ", expectedLabel)));
    }

    function setUp() public {
        // Deploy mock base registrar
        ethRegistryV1 = new MockBaseRegistrar();
        
        // Set up .eth domain in registry
        ethRegistryV1.addController(controller);
        
        // Deploy mock name wrapper
        nameWrapper = new MockNameWrapper();

        // Deploy mock bridge
        mockBridge = new MockL1Bridge();
        
        // Deploy mock L1 migrator
        mockL1Migrator = new MockL1Migrator();
        
        // Deploy migration controller
        migrationController = new L1UnlockedMigrationController(ethRegistryV1, INameWrapper(address(nameWrapper)), mockBridge, mockL1Migrator);
        
        // Calculate token ID for test label
        testTokenId = uint256(keccak256(bytes(testLabel)));
    }

    function test_constructor() public view {
        assertEq(address(migrationController.ethRegistryV1()), address(ethRegistryV1));
        assertEq(address(migrationController.nameWrapper()), address(nameWrapper));
        assertEq(address(migrationController.bridge()), address(mockBridge));
        assertEq(address(migrationController.l1Migrator()), address(mockL1Migrator));
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
        
        // Check for migration event from the bridge
        _assertBridgeMigrationEvent(testLabel);
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
        
        // Get logs once and use for both assertions
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        // Check for migration event from the bridge
        _assertBridgeMigrationEventWithLogs(testLabel, entries);
        
        // Check for L1 migrator event since toL1 is true
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
        
        // Check for migration event from the bridge
        _assertBridgeMigrationEvent(testLabel);
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
        
        // Get logs once and use for both assertions
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        // Check for migration event from the bridge
        _assertBridgeMigrationEventWithLogs(testLabel, entries);
        
        // Check for L1 migrator event since toL1 is true
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
        
        uint256 migratedEventCount = _countBridgeMigrationEvents(tokenIds);
        assertEq(migratedEventCount, 2, "Incorrect number of NameMigratedToL2 events");
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
        migrationDataArray[1] = _createMigrationDataWithL1Flag(label2, true);  // To both L1 and L2
        
        bytes memory data = abi.encode(migrationDataArray);
        
        vm.recordLogs();
        
        vm.prank(user);
        nameWrapper.safeBatchTransferFrom(user, address(migrationController), tokenIds, amounts, data);
        
        // Get logs once and use for all assertions
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        // Check that both names were migrated to L2
        uint256 migratedEventCount = _countBridgeMigrationEventsWithLogs(tokenIds, entries);
        assertEq(migratedEventCount, 2, "Incorrect number of NameMigratedToL2 events");
        
        // Check that only the second name was migrated to L1
        _assertL1MigratorEvent(label2, entries);
        
        // Verify the first name was NOT migrated to L1 by checking event count
        uint256 l1MigratorEventCount = 0;
        bytes32 expectedSig = keccak256("MockMigrateFromV1Called((string,address,address,address,uint256,uint64))");
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].emitter == address(mockL1Migrator) && entries[i].topics[0] == expectedSig) {
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
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(L1UnlockedMigrationController.MigrationNotSupported.selector));
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
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(L1UnlockedMigrationController.MigrationNotSupported.selector));
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
        
        vm.prank(address(nameWrapper));
        vm.expectRevert(abi.encodeWithSelector(L1UnlockedMigrationController.MigrationNotSupported.selector));
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
        
        vm.prank(address(nameWrapper));
        vm.expectRevert(abi.encodeWithSelector(L1UnlockedMigrationController.MigrationNotSupported.selector));
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
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(L1UnlockedMigrationController.TokenIdMismatch.selector, testTokenId, expectedTokenId));
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
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(L1UnlockedMigrationController.TokenIdMismatch.selector, testTokenId, expectedTokenId));
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
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(L1UnlockedMigrationController.TokenIdMismatch.selector, tokenId2, expectedTokenId));
        nameWrapper.safeBatchTransferFrom(user, address(migrationController), tokenIds, amounts, data);
    }
} 