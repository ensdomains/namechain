// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import "../src/common/RegistryDatastore.sol";
import "../src/common/IRegistry.sol";
import {L1EjectionController} from "../src/L1/L1EjectionController.sol";
import {EjectionController} from "../src/common/EjectionController.sol";
import {EnhancedAccessControl} from "../src/common/EnhancedAccessControl.sol";
import "../src/common/IRegistryMetadata.sol";
import {RegistryRolesMixin} from "../src/common/RegistryRolesMixin.sol";
import "../src/common/BaseRegistry.sol";
import "../src/common/IStandardRegistry.sol";
import "../src/common/NameUtils.sol";
import {PermissionedRegistry} from "../src/common/PermissionedRegistry.sol";
import {IPermissionedRegistry} from "../src/common/IPermissionedRegistry.sol";

contract MockRegistryMetadata is IRegistryMetadata {
    function tokenUri(uint256) external pure override returns (string memory) {
        return "";
    }
}

contract TestL1EjectionController is Test, ERC1155Holder, RegistryRolesMixin, EnhancedAccessControl {
    RegistryDatastore datastore;
    PermissionedRegistry registry;
    MockL1EjectionController ejectionController;
    MockRegistryMetadata registryMetadata;
    address constant MOCK_RESOLVER = address(0xabcd);
    address user = address(0x1234);

    uint256 labelHash = uint256(keccak256("test"));
    string testLabel = "test";

    function supportsInterface(bytes4 /*interfaceId*/) public pure override(ERC1155Holder, EnhancedAccessControl) returns (bool) {
        return true;
    }

    /**
     * Helper method to create properly encoded data for the ERC1155 transfers
     */
    function _createEjectionData(
        address l2Owner,
        address l2Subregistry,
        address l2Resolver,
        uint64 expiryTime,
        uint256 roleBitmap
    ) internal pure returns (bytes memory) {
        EjectionController.TransferData memory transferData = EjectionController.TransferData({
            label: "",
            owner: l2Owner,
            subregistry: l2Subregistry,
            resolver: l2Resolver,
            expires: expiryTime,
            roleBitmap: roleBitmap
        });
        return abi.encode(transferData);
    }
    
    /**
     * Helper method to create properly encoded batch data for the ERC1155 batch transfers
     */
    function _createBatchEjectionData(
        address[] memory l2Owners,
        address[] memory l2Subregistries,
        address[] memory l2Resolvers,
        uint64[] memory expiryTimes,
        uint256[] memory roleBitmaps
    ) internal pure returns (bytes memory) {
        require(l2Owners.length == l2Subregistries.length && 
                l2Owners.length == l2Resolvers.length && 
                l2Owners.length == expiryTimes.length &&
                l2Owners.length == roleBitmaps.length, 
                "Array lengths must match");
                
        EjectionController.TransferData[] memory transferDataArray = new EjectionController.TransferData[](l2Owners.length);
        
        for (uint256 i = 0; i < l2Owners.length; i++) {
            transferDataArray[i] = EjectionController.TransferData({
                label: "",
                owner: l2Owners[i],
                subregistry: l2Subregistries[i],
                resolver: l2Resolvers[i],
                expires: expiryTimes[i],
                roleBitmap: roleBitmaps[i]
            });
        }
        
        return abi.encode(transferDataArray);
    }
    
    function setUp() public {
        datastore = new RegistryDatastore();
        registryMetadata = new MockRegistryMetadata();
        
        // Deploy the registry
        registry = new PermissionedRegistry(datastore, registryMetadata, ALL_ROLES);
        
        // Create the real controller with the correct registry
        ejectionController = new MockL1EjectionController(registry);

        // grant roles
        registry.grantRootRoles(ROLE_REGISTRAR | ROLE_RENEW, address(this));
        registry.grantRootRoles(ROLE_REGISTRAR | ROLE_RENEW, address(ejectionController));
    }

    function test_eject_from_namechain_unlocked() public {
        uint64 expiryTime = uint64(block.timestamp) + 86400;
        ejectionController.completeEjectionFromNamechain(
            testLabel, 
            address(this), 
            address(registry), 
            MOCK_RESOLVER, 
            expiryTime, 
            ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY,
            ""
        );
        
        (uint256 tokenId,,) = registry.getNameData(testLabel);
        assertEq(registry.ownerOf(tokenId), address(this));
    }

    function test_eject_from_namechain_basic() public {
        uint64 expiryTime = uint64(block.timestamp) + 86400;
        uint256 expectedRoles = ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY;
        address subregistry = address(0x1234);
        ejectionController.completeEjectionFromNamechain(
            testLabel, 
            user, 
            subregistry, 
            MOCK_RESOLVER, 
            expiryTime, 
            expectedRoles,
            ""
        );
        
        (uint256 tokenId,,) = registry.getNameData(testLabel);
        assertEq(registry.ownerOf(tokenId), user);
        
        assertEq(address(registry.getSubregistry(testLabel)), subregistry);

        assertEq(registry.getResolver(testLabel), MOCK_RESOLVER);
        
        bytes32 resource = registry.getTokenIdResource(tokenId);
        assertTrue(registry.hasRoles(resource, expectedRoles, user), "Role bitmap should match the expected roles");
    }

    function test_eject_from_namechain_emits_events() public {
        vm.recordLogs();
        
        uint64 expiryTime = uint64(block.timestamp) + 86400;
        ejectionController.completeEjectionFromNamechain(
            testLabel, 
            address(this), 
            address(registry), 
            MOCK_RESOLVER, 
            expiryTime, 
            ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY,
            ""
        );

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundNewSubname = false;
        bool foundMockNameEjectedFromL2 = false;
        
        bytes32 newSubnameSig = keccak256("NewSubname(uint256,string)");
        bytes32 mockEjectedSig = keccak256("MockNameEjectedFromL2(string,address,address,address,uint64)");
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == newSubnameSig) {
                foundNewSubname = true;
            }
            if (entries[i].topics[0] == mockEjectedSig) {
                foundMockNameEjectedFromL2 = true;
            }
        }
        
        assertTrue(foundNewSubname, "NewSubname event not found");
        assertTrue(foundMockNameEjectedFromL2, "MockNameEjectedFromL2 event not found");
    }

    function test_Revert_eject_from_namechain_not_expired() public {
        // First register the name
        uint64 expiryTime = uint64(block.timestamp) + 86400;
        ejectionController.completeEjectionFromNamechain(
            testLabel, 
            address(this), 
            address(registry), 
            MOCK_RESOLVER, 
            expiryTime, 
            ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY,
            ""
        );
        
        // Try to eject again while not expired
        vm.expectRevert(abi.encodeWithSelector(IStandardRegistry.NameAlreadyRegistered.selector, testLabel));
        ejectionController.completeEjectionFromNamechain(
            testLabel, 
            address(this), 
            address(registry), 
            MOCK_RESOLVER, 
            expiryTime, 
            ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY,
            ""
        );
    }

    function test_updateExpiration() public {
        uint64 expiryTime = uint64(block.timestamp) + 100;
        ejectionController.completeEjectionFromNamechain(
            testLabel, 
            address(this), 
            address(registry), 
            MOCK_RESOLVER, 
            expiryTime, 
            ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY,
            ""
        );
        
        (uint256 tokenId,,) = registry.getNameData(testLabel);
        
        // Verify initial expiry was set
        (,uint64 initialExpiry,) = datastore.getSubregistry(address(registry), tokenId);
        assertEq(initialExpiry, expiryTime, "Initial expiry not set correctly");
        
        uint64 newExpiry = uint64(block.timestamp) + 200;
        
        ejectionController.syncRenewal(tokenId, newExpiry);

        // Verify new expiry was set
        (,uint64 updatedExpiry,) = datastore.getSubregistry(address(registry), tokenId);
        assertEq(updatedExpiry, newExpiry, "Expiry was not updated correctly");
    }

    function test_updateExpiration_emits_event() public {
        uint64 expiryTime = uint64(block.timestamp) + 100;
        ejectionController.completeEjectionFromNamechain(
            testLabel, 
            address(this), 
            address(registry), 
            MOCK_RESOLVER, 
            expiryTime, 
            ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY,
            ""
        );
        
        (uint256 tokenId,,) = registry.getNameData(testLabel);
        
        uint64 newExpiry = uint64(block.timestamp) + 200;

        vm.recordLogs();
        
        ejectionController.syncRenewal(tokenId, newExpiry);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool foundNameRenewed = false;
        bytes32 expectedSig = keccak256("NameRenewed(uint256,uint64,address)");
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == expectedSig) {
                foundNameRenewed = true;
                break;
            }
        }
        assertTrue(foundNameRenewed, "NameRenewed event not found");
    }

    function test_Revert_updateExpiration_expired_name() public {
        uint64 expiryTime = uint64(block.timestamp) + 100;
        ejectionController.completeEjectionFromNamechain(
            testLabel, 
            address(this), 
            address(registry), 
            MOCK_RESOLVER, 
            expiryTime, 
            ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY,
            ""
        );
        
        (uint256 tokenId,,) = registry.getNameData(testLabel);
        
        vm.warp(block.timestamp + 101);

        vm.expectRevert(abi.encodeWithSelector(IStandardRegistry.NameExpired.selector, tokenId));
        ejectionController.syncRenewal(tokenId, uint64(block.timestamp) + 200);
    }

    function test_Revert_updateExpiration_reduce_expiry() public {
        uint64 initialExpiry = uint64(block.timestamp) + 200;
        ejectionController.completeEjectionFromNamechain(
            testLabel, 
            address(this), 
            address(registry), 
            MOCK_RESOLVER, 
            initialExpiry, 
            ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY,
            ""
        );
        
        (uint256 tokenId,,) = registry.getNameData(testLabel);
        
        uint64 newExpiry = uint64(block.timestamp) + 100;

        vm.expectRevert(
            abi.encodeWithSelector(
                IStandardRegistry.CannotReduceExpiration.selector, initialExpiry, newExpiry
            )
        );
        ejectionController.syncRenewal(tokenId, newExpiry);
    }

    function test_migrateToNamechain() public {
        uint64 expiryTime = uint64(block.timestamp) + 86400;
        uint256 roleBitmap = ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY;
        
        // Register the name directly using the registry
        registry.register(testLabel, address(this), registry, MOCK_RESOLVER, roleBitmap, expiryTime);

        (uint256 tokenId,,) = registry.getNameData(testLabel);

        // Use helper method to create properly encoded data with expected values
        address expectedOwner = address(1);
        address expectedSubregistry = address(2);
        address expectedResolver = address(3);
        uint64 expectedExpiry = uint64(block.timestamp + 86400);
        uint256 expectedRoleBitmap = ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY;
        bytes memory data = _createEjectionData(
            expectedOwner, 
            expectedSubregistry, 
            expectedResolver, 
            expectedExpiry,
            expectedRoleBitmap
        );

        vm.recordLogs();
        registry.safeTransferFrom(address(this), address(ejectionController), tokenId, 1, data);

        // Check that the token is now owned by address(0)
        assertEq(registry.ownerOf(tokenId), address(0), "Token should have no owner after migration");

        // Check for event emission without trying to decode specific fields
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool eventReceived = false;
        bytes32 expectedSig = keccak256("MockNameEjectedToL2(uint256,address,address,address,uint64)");
        
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == expectedSig) {
                eventReceived = true;
                break;
            }
        }
        assertTrue(eventReceived, "MockNameEjectedToL2 event not found");
    }

    
    function test_onERC1155BatchReceived() public {
        // Register multiple names to migrate to L2
        uint64 expiryTime = uint64(block.timestamp) + 86400;
        
        string memory testLabel1 = "test1";
        string memory testLabel2 = "test2";
        string memory testLabel3 = "test3";
        
        // Register names directly using the registry
        registry.register(testLabel1, address(this), registry, MOCK_RESOLVER, ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY, expiryTime);
        registry.register(testLabel2, address(this), registry, MOCK_RESOLVER, ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY, expiryTime);
        registry.register(testLabel3, address(this), registry, MOCK_RESOLVER, ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY, expiryTime);
        
        (uint256 tokenId1,,) = registry.getNameData(testLabel1);
        (uint256 tokenId2,,) = registry.getNameData(testLabel2);
        (uint256 tokenId3,,) = registry.getNameData(testLabel3);
        
        // Verify we own the tokens
        assertEq(registry.ownerOf(tokenId1), address(this));
        assertEq(registry.ownerOf(tokenId2), address(this));
        assertEq(registry.ownerOf(tokenId3), address(this));
        
        // Set up batch transfer data
        uint256[] memory ids = new uint256[](3);
        ids[0] = tokenId1;
        ids[1] = tokenId2;
        ids[2] = tokenId3;
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1;
        amounts[1] = 1;
        amounts[2] = 1;
        
        // Create arrays for transfer data
        address[] memory owners = new address[](3);
        address[] memory subregistries = new address[](3);
        address[] memory resolvers = new address[](3);
        uint64[] memory expiries = new uint64[](3);
        uint256[] memory roleBitmaps = new uint256[](3);
        
        // Fill with different values for each token
        for (uint256 i = 0; i < 3; i++) {
            owners[i] = address(uint160(i + 1));
            subregistries[i] = address(uint160(i + 10));
            resolvers[i] = address(uint160(i + 100));
            expiries[i] = uint64(block.timestamp + 86400 * (i + 1));
            roleBitmaps[i] = ROLE_SET_RESOLVER | ROLE_SET_SUBREGISTRY | (i * 2); // Different roles for each token
        }
        
        // Create batch ejection data
        bytes memory data = _createBatchEjectionData(owners, subregistries, resolvers, expiries, roleBitmaps);
        
        // Execute batch transfer
        vm.recordLogs();
        registry.safeBatchTransferFrom(address(this), address(ejectionController), ids, amounts, data);
        
        // Verify all tokens were processed correctly
        for (uint256 i = 0; i < ids.length; i++) {
            assertEq(registry.ownerOf(ids[i]), address(0), "Token should have been relinquished");
        }
        
        // Check for batch event emission without trying to decode specific fields
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 batchEventsCount = 0;
        bytes32 expectedSig = keccak256("MockNameEjectedToL2(uint256,address,address,address,uint64)");
        
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == expectedSig) {
                batchEventsCount++;
            }
        }
        
        assertEq(batchEventsCount, 3, "Should have emitted 3 MockNameEjectedToL2 events");
    }
}

contract MockL1EjectionController is L1EjectionController {
    event MockNameEjectedToL2(uint256 tokenId, address l1Owner, address l1Subregistry, address l1Resolver, uint64 expires);
    event MockNameEjectedFromL2(string label, address l1Owner, address l1Subregistry, address l1Resolver, uint64 expires);
    
    constructor(IPermissionedRegistry _registry) L1EjectionController(_registry) {}
    
    function completeEjectionFromNamechain(
        string memory label,
        address l1Owner,
        address l1Subregistry,
        address l1Resolver,
        uint64 expires,
        uint256 roleBitmap,
        bytes memory /*data*/
    ) external {
        EjectionController.TransferData memory transferData = EjectionController.TransferData({
            label: label,
            owner: l1Owner,
            subregistry: l1Subregistry,
            resolver: l1Resolver,
            expires: expires,
            roleBitmap: roleBitmap
        });
        
        _completeEjectionFromL2(transferData);
        emit MockNameEjectedFromL2(label, l1Owner, l1Subregistry, l1Resolver, expires);
    }
    
    function syncRenewal(uint256 tokenId, uint64 newExpiry) external {
        _syncRenewal(tokenId, newExpiry);
    }
    
    /**
     * @dev Overridden to emit a mock event after calling the parent logic.
     */
    function _onEject(uint256[] memory tokenIds, EjectionController.TransferData[] memory transferDataArray) internal override {
        super._onEject(tokenIds, transferDataArray);
        
        // Emit events for each token that is ejected
        for (uint256 i = 0; i < tokenIds.length; i++) {
            EjectionController.TransferData memory transferData = transferDataArray[i];
            emit MockNameEjectedToL2(
                tokenIds[i],
                transferData.owner, 
                transferData.subregistry, 
                transferData.resolver, 
                transferData.expires
            );
        }
    }
}
