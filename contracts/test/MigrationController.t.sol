// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {IBaseRegistrar} from "@ens/contracts/ethregistrar/IBaseRegistrar.sol";
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
    
    constructor() ERC1155("https://metadata.ens.domains/") {}

    function wrapETH2LD(string memory label, address owner, uint16, address) external {
        uint256 tokenId = uint256(keccak256(bytes(label)));
        _mint(owner, tokenId, 1, "");
        _tokenOwners[tokenId] = owner;
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        return _tokenOwners[tokenId];
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

    constructor(IBaseRegistrar _ethRegistryV1) MigrationController(_ethRegistryV1) {}

    function _migrateUnwrappedEthName(
        address /*registry*/, 
        uint256 tokenId, 
        MigrationData memory migrationData
    ) internal override {
        emit MockUnwrappedEthNameMigrated(tokenId, migrationData.label, msg.sender);
    }
}

contract MockMigrationStrategy is IMigrationStrategy {
    event MockWrappedMigrationCalled(address registry, uint256[] tokenIds, MigrationData[] migrationDataArray);

    function migrateWrappedEthNames(
        address registry, 
        uint256[] memory tokenIds, 
        MigrationData[] memory migrationDataArray
    ) external override {
        emit MockWrappedMigrationCalled(registry, tokenIds, migrationDataArray);
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
        vm.expectRevert();
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
        vm.expectRevert();
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
        
        // Try to call onERC721Received when controller doesn't own the token
        vm.expectRevert();
        migrationController.onERC721Received(address(ethRegistryV1), user, testTokenId, data);
    }

    function test_migrateWrappedEthName_single() public {
        // Set migration strategy first
        migrationController.setStrategy(migrationStrategy);
        
        // Wrap a name (simulate)
        vm.prank(user);
        nameWrapper.wrapETH2LD(testLabel, user, 0, address(0));
        
        // Create migration data
        MigrationData memory migrationData = MigrationData({
            label: testLabel
        });
        bytes memory data = abi.encode(migrationData);
        
        vm.recordLogs();
        
        // Transfer wrapped token to migration controller
        vm.prank(user);
        nameWrapper.safeTransferFrom(user, address(migrationController), testTokenId, 1, data);
        
        // Check for strategy call event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundStrategyEvent = false;
        bytes32 expectedSig = keccak256("MockWrappedMigrationCalled(address,uint256[],(string)[])");
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == expectedSig) {
                foundStrategyEvent = true;
                break;
            }
        }
        assertTrue(foundStrategyEvent, "MockWrappedMigrationCalled event not found");
    }

    function test_migrateWrappedEthName_batch() public {
        // Set migration strategy first
        migrationController.setStrategy(migrationStrategy);
        
        // Wrap multiple names
        string memory testLabel1 = "test1";
        string memory testLabel2 = "test2";
        string memory testLabel3 = "test3";
        
        uint256 tokenId1 = uint256(keccak256(bytes(testLabel1)));
        uint256 tokenId2 = uint256(keccak256(bytes(testLabel2)));
        uint256 tokenId3 = uint256(keccak256(bytes(testLabel3)));
        
        // Wrap the names
        vm.startPrank(user);
        nameWrapper.wrapETH2LD(testLabel1, user, 0, address(0));
        nameWrapper.wrapETH2LD(testLabel2, user, 0, address(0));
        nameWrapper.wrapETH2LD(testLabel3, user, 0, address(0));
        vm.stopPrank();
        
        // Prepare batch transfer data
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;
        tokenIds[2] = tokenId3;
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1;
        amounts[1] = 1;
        amounts[2] = 1;
        
        MigrationData[] memory migrationDataArray = new MigrationData[](3);
        migrationDataArray[0] = MigrationData({label: testLabel1});
        migrationDataArray[1] = MigrationData({label: testLabel2});
        migrationDataArray[2] = MigrationData({label: testLabel3});
        
        bytes memory data = abi.encode(migrationDataArray);
        
        vm.recordLogs();
        
        // Batch transfer to migration controller
        vm.prank(user);
        nameWrapper.safeBatchTransferFrom(user, address(migrationController), tokenIds, amounts, data);
        
        // Check for strategy call event
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundStrategyEvent = false;
        bytes32 expectedSig = keccak256("MockWrappedMigrationCalled(address,uint256[],(string)[])");
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == expectedSig) {
                foundStrategyEvent = true;
                break;
            }
        }
        assertTrue(foundStrategyEvent, "MockWrappedMigrationCalled event not found");
    }

    function test_Revert_migrateWrappedEthName_no_strategy() public {
        // Don't set migration strategy
        
        // Create migration data
        MigrationData memory migrationData = MigrationData({
            label: testLabel
        });
        bytes memory data = abi.encode(migrationData);
        
        // Try to transfer without strategy set
        vm.prank(user);
        vm.expectRevert();
        nameWrapper.safeTransferFrom(user, address(migrationController), testTokenId, 1, data);
    }

    function test_Revert_migrateWrappedEthName_batch_no_strategy() public {
        // Don't set migration strategy
        
        // Prepare batch data
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = testTokenId;
        
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1;
        
        MigrationData[] memory migrationDataArray = new MigrationData[](1);
        migrationDataArray[0] = MigrationData({label: testLabel});
        
        bytes memory data = abi.encode(migrationDataArray);
        
        // Try to batch transfer without strategy set
        vm.prank(user);
        vm.expectRevert();
        nameWrapper.safeBatchTransferFrom(user, address(migrationController), tokenIds, amounts, data);
    }

    function test_supportsInterface() public view {
        assertTrue(migrationController.supportsInterface(0x01ffc9a7)); // ERC165
        assertTrue(migrationController.supportsInterface(0x150b7a02)); // ERC721Receiver
        // Note: ERC1155Receiver interface support depends on implementation details
    }
} 