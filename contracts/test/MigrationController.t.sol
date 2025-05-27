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
import {MigrationController} from "../src/common/MigrationController.sol";
import {IMigrationStrategy, MigrationData} from "../src/common/IMigration.sol";

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

    function reclaim(uint256 id, address /*owner*/) external override {
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
    mapping(uint256 => uint32) private _tokenFuses; // Added to store fuses
    
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
        return (_tokenOwners[tokenId], _tokenFuses[tokenId], 0); // Return owner, fuses, and 0 for expiry
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
}

contract MockMigrationController is MigrationController {
    event MockUnwrappedEthNameMigrated(uint256 tokenId, string label, address owner);
    event MockUnlockedEthNameMigrated(uint256 tokenId, string label, address owner);

    constructor(IBaseRegistrar _ethRegistryV1) MigrationController(_ethRegistryV1) {}

    function _migrateUnwrappedEthName(
        address /*registry*/, 
        uint256 tokenId, 
        MigrationData memory migrationData
    ) internal override {
        emit MockUnwrappedEthNameMigrated(tokenId, migrationData.label, msg.sender);
    }

    function _migrateUnlockedEthName(
        address /*registry*/,
        uint256 tokenId,
        MigrationData memory migrationData
    ) internal override {
        emit MockUnlockedEthNameMigrated(tokenId, migrationData.label, msg.sender);
    }
}

contract MockMigrationStrategy is IMigrationStrategy {
    event MockLockedMigrationCalled(address registry, uint256 tokenId, MigrationData migrationData);

    function migrateLockedEthName(
        address registry, 
        uint256 tokenId, 
        MigrationData memory migrationData
    ) external override {
        emit MockLockedMigrationCalled(registry, tokenId, migrationData);
    }
}

contract TestMigrationController is Test, ERC1155Holder, ERC721Holder {
    MockBaseRegistrar ethRegistryV1;
    MockNameWrapper nameWrapper;
    MockMigrationController migrationController;
    MockMigrationStrategy migrationStrategy;

    address user = address(0x1234);
    address controller = address(0x5678);
    
    string testLabel = "test";
    uint256 testTokenId;

    function setUp() public {
        // Deploy mock base registrar
        ethRegistryV1 = new MockBaseRegistrar();
        
        // Set up .eth domain in registry
        ethRegistryV1.addController(controller);
        
        // Deploy mock name wrapper
        nameWrapper = new MockNameWrapper();
        
        // Deploy migration controller
        migrationController = new MockMigrationController(ethRegistryV1);
        
        // Deploy migration strategy
        migrationStrategy = new MockMigrationStrategy();
        
        // Calculate token ID for test label
        testTokenId = uint256(keccak256(bytes(testLabel)));
    }

    function test_constructor() public {
        assertEq(address(migrationController.ethRegistryV1()), address(ethRegistryV1));
        assertEq(address(migrationController.strategy()), address(0));
        assertEq(migrationController.owner(), address(this));
    }

    function test_setStrategy() public {
        vm.recordLogs();
        
        migrationController.setStrategy(migrationStrategy);
        
        assertEq(address(migrationController.strategy()), address(migrationStrategy));
        
        // Check for StrategySet event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundStrategySet = false;
        bytes32 expectedSig = keccak256("StrategySet(address)");
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == expectedSig) {
                foundStrategySet = true;
                break;
            }
        }
        assertTrue(foundStrategySet, "StrategySet event not found");
    }

    function test_Revert_setStrategy_not_owner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        migrationController.setStrategy(migrationStrategy);
    }

    function test_migrateUnwrappedEthName() public {
        // Register a name in the v1 registrar
        vm.prank(controller);
        ethRegistryV1.register(testTokenId, user, 86400);
        
        // Verify user owns the token
        assertEq(ethRegistryV1.ownerOf(testTokenId), user);
        
        // Create migration data
        MigrationData memory migrationData = MigrationData({
            label: testLabel
        });
        bytes memory data = abi.encode(migrationData);
        
        vm.recordLogs();
        
        // Transfer to migration controller (simulating migration)
        vm.prank(user);
        ethRegistryV1.safeTransferFrom(user, address(migrationController), testTokenId, data);
        
        // Verify the migration controller now owns the token
        assertEq(ethRegistryV1.ownerOf(testTokenId), address(migrationController));
        
        // Check for migration event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundMigrationEvent = false;
        bytes32 expectedSig = keccak256("MockUnwrappedEthNameMigrated(uint256,string,address)");
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == expectedSig) {
                foundMigrationEvent = true;
                break;
            }
        }
        assertTrue(foundMigrationEvent, "MockUnwrappedEthNameMigrated event not found");
    }

    function test_Revert_migrateUnwrappedEthName_wrong_caller() public {
        // Register a name in the v1 registrar
        vm.prank(controller);
        ethRegistryV1.register(testTokenId, user, 86400);
        
        // Create migration data
        MigrationData memory migrationData = MigrationData({
            label: testLabel
        });
        bytes memory data = abi.encode(migrationData);
        
        // Try to transfer from wrong registry
        vm.expectRevert(abi.encodeWithSelector(MigrationController.CallerNotEthRegistryV1.selector, address(this)));
        migrationController.onERC721Received(address(this), user, testTokenId, data);
    }

    function test_Revert_migrateUnwrappedEthName_not_owner() public {
        // Register a name in the v1 registrar
        vm.prank(controller);
        ethRegistryV1.register(testTokenId, user, 86400);
        
        // Create migration data
        MigrationData memory migrationData = MigrationData({
            label: testLabel
        });
        bytes memory data = abi.encode(migrationData);
        
        // Try to call onERC721Received directly when migration controller doesn't own the token
        // This should fail with CallerNotEthRegistryV1 because we're calling it directly
        vm.expectRevert(abi.encodeWithSelector(MigrationController.CallerNotEthRegistryV1.selector, address(this)));
        migrationController.onERC721Received(address(this), user, testTokenId, data);
    }

    function test_Revert_migrateUnwrappedEthName_controller_not_owner() public {
        // Register a name in the v1 registrar but don't transfer it to migration controller
        vm.prank(controller);
        ethRegistryV1.register(testTokenId, user, 86400);
        
        // Create migration data
        MigrationData memory migrationData = MigrationData({
            label: testLabel
        });
        bytes memory data = abi.encode(migrationData);
        
        // Mock the call as if it came from ethRegistryV1 but migration controller doesn't own the token
        vm.prank(address(ethRegistryV1));
        vm.expectRevert(abi.encodeWithSelector(MigrationController.NotOwner.selector, testTokenId));
        migrationController.onERC721Received(address(ethRegistryV1), user, testTokenId, data);
    }

    function test_migrateUnlockedWrappedEthName_single() public {
        // Set migration strategy first (though not strictly needed for unlocked)
        migrationController.setStrategy(migrationStrategy);
        
        // Wrap a name (simulate)
        vm.prank(user);
        nameWrapper.wrapETH2LD(testLabel, user, 0, address(0));
        // Ensure fuses are 0 (unlocked)
        nameWrapper.setFuses(testTokenId, 0);
        
        // Create migration data
        MigrationData memory migrationData = MigrationData({
            label: testLabel
        });
        bytes memory data = abi.encode(migrationData);
        
        vm.recordLogs();
        
        // Transfer wrapped token to migration controller
        vm.prank(user);
        nameWrapper.safeTransferFrom(user, address(migrationController), testTokenId, 1, data);
        
        // Check for unlocked migration event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundMigrationEvent = false;
        bytes32 expectedSig = keccak256("MockUnlockedEthNameMigrated(uint256,string,address)");
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == expectedSig) {
                foundMigrationEvent = true;
                break;
            }
        }
        assertTrue(foundMigrationEvent, "MockUnlockedEthNameMigrated event not found");
    }

    function test_migrateLockedWrappedEthName_single() public {
        // Set migration strategy first
        migrationController.setStrategy(migrationStrategy);
        
        // Wrap a name (simulate)
        vm.prank(user);
        nameWrapper.wrapETH2LD(testLabel, user, 0, address(0));
        // Set fuses to indicate locked (CANNOT_UNWRAP)
        nameWrapper.setFuses(testTokenId, CANNOT_UNWRAP);
        
        // Create migration data
        MigrationData memory migrationData = MigrationData({
            label: testLabel
        });
        bytes memory data = abi.encode(migrationData);
        
        vm.recordLogs();
        
        // Transfer wrapped token to migration controller
        vm.prank(user);
        nameWrapper.safeTransferFrom(user, address(migrationController), testTokenId, 1, data);
        
        // Check for strategy call event for locked names
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundStrategyEvent = false;
        bytes32 expectedSig = keccak256("MockLockedMigrationCalled(address,uint256,(string))");
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == expectedSig) {
                foundStrategyEvent = true;
                break;
            }
        }
        assertTrue(foundStrategyEvent, "MockLockedMigrationCalled event not found");
    }

    function test_migrateWrappedEthName_batch_allUnlocked() public {
        // Set migration strategy (though not strictly needed for all unlocked)
        migrationController.setStrategy(migrationStrategy);
        
        string memory label1 = "unlocked1";
        string memory label2 = "unlocked2";
        uint256 tokenId1 = uint256(keccak256(bytes(label1)));
        uint256 tokenId2 = uint256(keccak256(bytes(label2)));

        vm.startPrank(user);
        nameWrapper.wrapETH2LD(label1, user, 0, address(0));
        nameWrapper.setFuses(tokenId1, 0); // Unlocked
        nameWrapper.wrapETH2LD(label2, user, 0, address(0));
        nameWrapper.setFuses(tokenId2, 0); // Unlocked
        vm.stopPrank();
        
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;
        
        MigrationData[] memory migrationDataArray = new MigrationData[](2);
        migrationDataArray[0] = MigrationData({label: label1});
        migrationDataArray[1] = MigrationData({label: label2});
        
        bytes memory data = abi.encode(migrationDataArray);
        
        vm.recordLogs();
        
        vm.prank(user);
        nameWrapper.safeBatchTransferFrom(user, address(migrationController), tokenIds, amounts, data);
        
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 unlockedEventCount = 0;
        bytes32 unlockedSig = keccak256("MockUnlockedEthNameMigrated(uint256,string,address)");

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == unlockedSig) {
                (uint256 eventTokenId,,) = abi.decode(entries[i].data, (uint256, string, address));
                if (eventTokenId == tokenId1 || eventTokenId == tokenId2) {
                    unlockedEventCount++;
                }
            }
        }
        assertEq(unlockedEventCount, 2, "Incorrect number of MockUnlockedEthNameMigrated events");
    }

    function test_migrateWrappedEthName_batch_allLocked() public {
        migrationController.setStrategy(migrationStrategy);
        
        string memory label1 = "locked1";
        string memory label2 = "locked2";
        uint256 tokenId1 = uint256(keccak256(bytes(label1)));
        uint256 tokenId2 = uint256(keccak256(bytes(label2)));

        vm.startPrank(user);
        nameWrapper.wrapETH2LD(label1, user, 0, address(0));
        nameWrapper.setFuses(tokenId1, CANNOT_UNWRAP); // Locked
        nameWrapper.wrapETH2LD(label2, user, 0, address(0));
        nameWrapper.setFuses(tokenId2, CANNOT_UNWRAP); // Locked
        vm.stopPrank();
        
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1;
        amounts[1] = 1;
        
        MigrationData[] memory migrationDataArray = new MigrationData[](2);
        migrationDataArray[0] = MigrationData({label: label1});
        migrationDataArray[1] = MigrationData({label: label2});
        
        bytes memory data = abi.encode(migrationDataArray);
        
        vm.recordLogs();
        
        vm.prank(user);
        nameWrapper.safeBatchTransferFrom(user, address(migrationController), tokenIds, amounts, data);
        
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 lockedEventCount = 0;
        bytes32 lockedSig = keccak256("MockLockedMigrationCalled(address,uint256,(string))");

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == lockedSig) {
                (,,MigrationData memory mData) = abi.decode(entries[i].data, (address, uint256, MigrationData));
                uint256 currentTokenId = uint256(keccak256(bytes(mData.label)));
                 if (currentTokenId == tokenId1 || currentTokenId == tokenId2) {
                    lockedEventCount++;
                }
            }
        }
        assertEq(lockedEventCount, 2, "Incorrect number of MockLockedMigrationCalled events");
    }

    function test_Revert_migrateWrappedEthName_no_strategy_locked() public {
        // Don't set migration strategy
        
        // First wrap a name so the user actually owns it
        vm.prank(user);
        nameWrapper.wrapETH2LD(testLabel, user, 0, address(0));
        nameWrapper.setFuses(testTokenId, CANNOT_UNWRAP); // Mark as locked
        
        // Create migration data
        MigrationData memory migrationData = MigrationData({
            label: testLabel
        });
        bytes memory data = abi.encode(migrationData);
        
        // Try to transfer without strategy set (should revert for locked name)
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(MigrationController.NoMigrationStrategySet.selector));
        nameWrapper.safeTransferFrom(user, address(migrationController), testTokenId, 1, data);
    }

    function test_Revert_migrateWrappedEthName_batch_no_strategy_locked() public {
        // Don't set migration strategy
        
        // First wrap a name so the user actually owns it
        vm.prank(user);
        nameWrapper.wrapETH2LD(testLabel, user, 0, address(0));
        nameWrapper.setFuses(testTokenId, CANNOT_UNWRAP); // Mark as locked
        
        // Prepare batch data
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = testTokenId;
        
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;
        
        MigrationData[] memory migrationDataArray = new MigrationData[](1);
        migrationDataArray[0] = MigrationData({label: testLabel});
        
        bytes memory data = abi.encode(migrationDataArray);
        
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InvalidReceiver.selector, address(migrationController)));
        nameWrapper.safeBatchTransferFrom(user, address(migrationController), tokenIds, amounts, data);
    }

    function test_supportsInterface() public view {
        assertTrue(migrationController.supportsInterface(type(IERC165).interfaceId));
        assertTrue(migrationController.supportsInterface(type(IERC721Receiver).interfaceId));
        assertTrue(migrationController.supportsInterface(type(IERC1155Receiver).interfaceId));
        assertTrue(migrationController.supportsInterface(type(Ownable).interfaceId));
    }
} 